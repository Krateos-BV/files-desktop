/*
 * SPDX-FileCopyrightText: 2026 XeniaCloud
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

// XEN-372: turn SIGTERM, SIGINT and SIGHUP into a normal application quit on
// Linux and other non-Apple Unix systems.
//
// Without this the default signal action kills the client at once, so the
// aboutToQuit cleanup never runs: no folder is unloaded, OpenVFS::stop() is never
// called, and openvfs keeps running with its FUSE mount after the client is gone
// (session logout, shutdown, `kill`, an updater replacing the AppImage).
//
// The handler only writes one byte to a socketpair (async-signal-safe). A
// QSocketNotifier on the other end calls QCoreApplication::quit() from the event
// loop, which is the same path as "Quit" in the tray and `--quit`. After the first
// signal the handler restores the default action, so a second signal still
// terminates a client that hangs while shutting down.

#include <QObject>

class QSocketNotifier;

namespace OCC::Xenia {

class UnixSignalQuit : public QObject
{
    Q_OBJECT
public:
    // Installs the handlers. Call once, after the QApplication exists.
    // Returns nullptr (and logs) if the socketpair or sigaction setup fails.
    static UnixSignalQuit *install(QObject *parent);

private:
    explicit UnixSignalQuit(QObject *parent);
    void onSignalReadable();

    QSocketNotifier *_notifier = nullptr;
};

} // namespace OCC::Xenia
