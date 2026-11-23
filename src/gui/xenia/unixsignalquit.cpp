/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "unixsignalquit.h"

#include <QCoreApplication>
#include <QLoggingCategory>
#include <QSocketNotifier>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcXeniaSignal, "nextcloud.gui.xenia.signal", QtInfoMsg)

namespace {

// [0] is written by the signal handler, [1] is read by the notifier.
int s_signalFds[2] = {-1, -1};

constexpr int handledSignals[] = {SIGTERM, SIGINT, SIGHUP};

extern "C" void xeniaQuitSignalHandler(int signum)
{
    // Only async-signal-safe calls here.
    const int savedErrno = errno;

    // A second signal while we are still shutting down kills the process the
    // default way, so a hung shutdown can never make the client unkillable.
    struct sigaction dfl{};
    dfl.sa_handler = SIG_DFL;
    sigemptyset(&dfl.sa_mask);
    for (const int sig : handledSignals) {
        sigaction(sig, &dfl, nullptr);
    }

    const unsigned char byte = static_cast<unsigned char>(signum);
    [[maybe_unused]] const auto written = ::write(s_signalFds[0], &byte, sizeof(byte));
    errno = savedErrno;
}

bool setCloexecNonblock(int fd)
{
    const int fdFlags = ::fcntl(fd, F_GETFD);
    const int flFlags = ::fcntl(fd, F_GETFL);
    return fdFlags != -1 && flFlags != -1 && ::fcntl(fd, F_SETFD, fdFlags | FD_CLOEXEC) != -1
        && ::fcntl(fd, F_SETFL, flFlags | O_NONBLOCK) != -1;
}

} // namespace

namespace OCC::Xenia {

UnixSignalQuit *UnixSignalQuit::install(QObject *parent)
{
    if (s_signalFds[0] != -1) {
        qCWarning(lcXeniaSignal) << "signal handlers already installed";
        return nullptr;
    }

    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, s_signalFds) != 0) {
        qCWarning(lcXeniaSignal) << "socketpair failed, SIGTERM will not run the quit cleanup:" << std::strerror(errno);
        s_signalFds[0] = s_signalFds[1] = -1;
        return nullptr;
    }
    // Close-on-exec so openvfs and other helpers do not inherit the pair,
    // non-blocking so the handler can never block on a full buffer.
    if (!setCloexecNonblock(s_signalFds[0]) || !setCloexecNonblock(s_signalFds[1])) {
        qCWarning(lcXeniaSignal) << "fcntl failed on the signal socketpair:" << std::strerror(errno);
        ::close(s_signalFds[0]);
        ::close(s_signalFds[1]);
        s_signalFds[0] = s_signalFds[1] = -1;
        return nullptr;
    }

    auto *self = new UnixSignalQuit(parent);

    struct sigaction sa{};
    sa.sa_handler = xeniaQuitSignalHandler;
    sigemptyset(&sa.sa_mask);
    for (const int sig : handledSignals) {
        sigaddset(&sa.sa_mask, sig);
    }
    sa.sa_flags = SA_RESTART;
    for (const int sig : handledSignals) {
        if (::sigaction(sig, &sa, nullptr) != 0) {
            qCWarning(lcXeniaSignal) << "sigaction failed for signal" << sig << std::strerror(errno);
        }
    }

    qCInfo(lcXeniaSignal) << "SIGTERM, SIGINT and SIGHUP now quit the application cleanly";
    return self;
}

UnixSignalQuit::UnixSignalQuit(QObject *parent)
    : QObject(parent)
    , _notifier(new QSocketNotifier(s_signalFds[1], QSocketNotifier::Read, this))
{
    connect(_notifier, &QSocketNotifier::activated, this, &UnixSignalQuit::onSignalReadable);
}

void UnixSignalQuit::onSignalReadable()
{
    unsigned char byte = 0;
    const auto n = ::read(s_signalFds[1], &byte, sizeof(byte));
    if (n != 1) {
        return;
    }
    // One quit is enough; later bytes (if any) are ignored.
    _notifier->setEnabled(false);
    qCInfo(lcXeniaSignal) << "received signal" << int(byte) << "(" << ::strsignal(byte) << "), quitting cleanly";
    QCoreApplication::quit();
}

} // namespace OCC::Xenia
