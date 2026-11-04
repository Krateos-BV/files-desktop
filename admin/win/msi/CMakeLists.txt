# SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-2.0-or-later
if(CMAKE_SIZEOF_VOID_P MATCHES 4)
    set(MSI_BUILD_ARCH x86)
else()
    set(MSI_BUILD_ARCH x64)
endif()

string(SUBSTRING ${GIT_SHA1} 0 7 GIT_REVISION)

set(VERSION "${MIRALL_VERSION_MAJOR}.${MIRALL_VERSION_MINOR}.${MIRALL_VERSION_PATCH}.${MIRALL_VERSION_BUILD}")

if (NOT DEFINED MIRALL_VERSION_SUFFIX OR MIRALL_VERSION_SUFFIX MATCHES "git")
    set(VERSION_SUFFIX "")
else()
    set(VERSION_SUFFIX "-${MIRALL_VERSION_SUFFIX}")
endif()

set(MSI_INSTALLER_FILENAME "${APPLICATION_SHORTNAME}-${VERSION}${VERSION_SUFFIX}-${MSI_BUILD_ARCH}.msi")

# The app icon is both a file in the harvested install dir and a WiX Icon Id, and a
# WiX Id may only hold letters, digits, '_' and '.'. A branded APPLICATION_ICON_NAME
# such as "Xenia Files" has a space, so use a sanitised name for both.
string(REGEX REPLACE "[^A-Za-z0-9_.]" "" MSI_APP_ICON_NAME "${APPLICATION_ICON_NAME}")

# The client build generates the .ico (src/gui, ecm_add_app_icon) but never installs
# it, and Nextcloud.wxs expects it next to the executable in the harvested dir.
install(FILES "${CMAKE_BINARY_DIR}/src/gui/${APPLICATION_ICON_NAME}.ico"
    DESTINATION bin
    RENAME "${MSI_APP_ICON_NAME}.ico")

configure_file(RegistryCleanup.vbs.in ${CMAKE_CURRENT_BINARY_DIR}/RegistryCleanup.vbs)
configure_file(OEM.wxi.in ${CMAKE_CURRENT_BINARY_DIR}/OEM.wxi)
configure_file(collect-transform.xsl.in ${CMAKE_CURRENT_BINARY_DIR}/collect-transform.xsl)
configure_file(make-msi.bat.in ${CMAKE_CURRENT_BINARY_DIR}/make-msi.bat)

install(FILES
        ${CMAKE_CURRENT_BINARY_DIR}/OEM.wxi
        ${CMAKE_CURRENT_BINARY_DIR}/collect-transform.xsl
        ${CMAKE_CURRENT_BINARY_DIR}/make-msi.bat
        EnsureACL.js
        Platform.wxi
        Nextcloud.wxs
        ${CMAKE_CURRENT_BINARY_DIR}/RegistryCleanup.vbs
        RegistryCleanupCustomAction.wxs
        gui/banner.bmp
        gui/dialog.bmp
    DESTINATION msi/)
