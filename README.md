<!--
  - SPDX-FileCopyrightText: 2017 Nextcloud GmbH and Nextcloud contributors
  - SPDX-FileCopyrightText: 2011 Nextcloud GmbH and Nextcloud contributors
  - SPDX-FileCopyrightText: 2026 XeniaCloud
  - SPDX-License-Identifier: GPL-2.0-or-later
-->
# Xenia Files Desktop

[![REUSE status](https://api.reuse.software/badge/github.com/Krateos-BV/files-desktop)](https://api.reuse.software/info/github.com/Krateos-BV/files-desktop)

> Independently maintained desktop sync client for Xenia Files, based on the [Nextcloud Desktop Client](https://github.com/nextcloud/desktop) (GPLv2-or-later). Not affiliated with or endorsed by Nextcloud GmbH.

The desktop app to synchronize files from your [XeniaCloud](https://xeniacloud.eu) account with your computer, available for Windows, macOS and Linux.

<p align="center">
    <img src="doc/images/main_dialog_christine.png" alt="Desktop Client" width="450">
</p>

## Upstream & license 📜

Xenia Files Desktop is a rebrand of [nextcloud/desktop](https://github.com/nextcloud/desktop), forked under its GPLv2-or-later license, which permits forking provided Nextcloud's own trademarks and branding are not carried over — the app name, icons and server URL defaults here have been changed accordingly; the underlying code and functionality are otherwise unchanged from upstream unless noted in this fork's own commit history.

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version. This program is distributed WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

## Getting help 🛟

This is an independently maintained fork — upstream's help forum, docs site, and issue tracker are for the Nextcloud desktop client, not Xenia Files, and won't be able to help with anything specific to this fork or to a XeniaCloud account. For support with Xenia Files Desktop or your XeniaCloud account, contact XeniaCloud support directly.

## Downloads 🚀

This fork is not currently distributed via a public release channel — no GitHub Releases exist on this repo yet. Builds are produced by this repository's own CI as unsigned artifacts.

## Bug fixing and development 🛠️

> [!TIP]
> For contributors on macOS, see the [macOS development guide](./doc/macOS-development.md).

> [!NOTE]
> Find the system requirements and instructions on [how to work with KDE Craft in our desktop client blueprints repository](https://github.com/nextcloud/craft-blueprints-nextcloud/) (this fork follows upstream's build tooling).

### System requirements
- Windows 10, Windows 11, macOS 13 Ventura (or newer) or Linux
- [🔽 Inkscape (to generate icons)](https://inkscape.org/release/)
- Developer tools: cmake, clang/gcc/g++:
- Qt6 since 3.14, Qt5 for earlier versions
- OpenSSL
- [🔽 QtKeychain](https://github.com/frankosterfeld/qtkeychain)
- SQLite
- [Xcode](https://developer.apple.com/xcode/) (only on macOS)

Optional recommendations:

- [Qt Creator IDE](https://www.qt.io/product/development-tools)
- [delta: A viewer for git and diff output](https://github.com/dandavison/delta)

### Build

Step by step instructions on how to build the client to contribute.

1. Clone this repository: `git clone https://github.com/Krateos-BV/files-desktop.git`
2. Create build directory: `mkdir <build directory>`
3. Navigate into build directory: `cd <build directory>`
4. Compile: `cmake -S <cloned repo> -B build -DCMAKE_PREFIX_PATH=<dependencies> -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=. -DNEXTCLOUD_DEV=ON`

> [!TIP]
> The cmake variable NEXTCLOUD_DEV allows you to run your own build of the client while developing in parallel with an installed version of the client.

### Test servers

The easiest way to have a local Nextcloud server to develop, debug and test the client against is [the Nextcloud Docker image](https://github.com/nextcloud/docker).
The following example shows how to deploy a Nextcloud Docker container on the local host which will be removed again as soon as the command is interrupted.
Note that this requires Docker to be installed in your developer environment.

```bash
docker run \
    --rm \
    --publish 8080:80 \
    --env SQLITE_DATABASE=nextcloud.sqlite \
    --env NEXTCLOUD_ADMIN_USER=admin \
    --env NEXTCLOUD_ADMIN_PASSWORD=admin \
    nextcloud
```

This simple test server already suffices in most cases. For more advanced server test deployments upstream also recommends [Nextcloud development environment on Docker Compose](https://juliusknorr.github.io/nextcloud-docker-dev/).
