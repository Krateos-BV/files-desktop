# SPDX-FileCopyrightText: 2017 Nextcloud GmbH and Nextcloud contributors
# SPDX-FileCopyrightText: 2012 ownCloud GmbH
# SPDX-License-Identifier: GPL-2.0-or-later
#
# keep the application name and short name the same or different for dev and prod build
# or some migration logic will behave differently for each build
if(NEXTCLOUD_DEV)
    set( APPLICATION_NAME       "NextcloudDev" )
    set( APPLICATION_SHORTNAME  "NextcloudDev" )
    set( APPLICATION_EXECUTABLE "nextclouddev" )
    set( APPLICATION_ICON_NAME  "Nextcloud" )
else()
    set( APPLICATION_NAME       "Xenia Files" )
    set( APPLICATION_SHORTNAME  "Xenia Files" )
    set( APPLICATION_EXECUTABLE "xenia-files" )
    set( APPLICATION_ICON_NAME  "${APPLICATION_SHORTNAME}" )
endif()

set( APPLICATION_CONFIG_NAME "${APPLICATION_EXECUTABLE}" )
set( APPLICATION_DOMAIN     "xeniacloud.eu" )
set( APPLICATION_VENDOR     "XeniaCloud" )
# XNT-113: the updater is disabled for Xenia builds (see BUILD_UPDATER below), so
# nothing fetches this URL. It stays defined because Theme::updateCheckUrl() reads
# APPLICATION_UPDATE_URL unconditionally, and config.h.in drops the define entirely
# when the value is empty. The placeholder host is not live yet; it must not be
# pointed at a working channel until that channel serves signed artifacts.
set( APPLICATION_UPDATE_URL "https://updates.xeniacloud.eu/client/" CACHE STRING "URL for updater" )
set( APPLICATION_HELP_URL   "https://xeniacloud.eu" CACHE STRING "URL for the help menu" )

# Default macOS builds (Nextcloud + NextcloudDev) use the Icon Composer (.icon)
# format for the app icon. That format can only be compiled by a recent enough
# toolchain (Xcode 26 ships the actool that understands .icon, and macOS 26
# provides the matching SDK), so we gate the modern pipeline on the build
# environment. Older environments — and branded customer builds, which use a
# different APPLICATION_NAME and ship their own colourful icon SVG — fall back
# to the historical Inkscape + ECM (ecm_add_app_icon) .icns pipeline instead.
#
# The Xcode/actool version is the real capability gate; the macOS check is a
# coarse secondary guard. Detection runs every configure and is intentionally
# NOT cached, so the decision self-heals once the build host is upgraded without
# requiring a clean reconfigure. Pass -DMACOS_USE_ICON_COMPOSER=ON/OFF to
# override auto-detection entirely.
if(APPLE)
    execute_process(COMMAND sw_vers -productVersion
        OUTPUT_VARIABLE _macos_product_version RESULT_VARIABLE _macos_ver_result
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    execute_process(COMMAND xcodebuild -version
        OUTPUT_VARIABLE _xcodebuild_version_raw RESULT_VARIABLE _xcode_ver_result
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)

    set(MACOS_ICON_COMPOSER_TOOLCHAIN_SUPPORTED OFF)
    if(_macos_ver_result EQUAL 0 AND _xcode_ver_result EQUAL 0)
        string(REGEX MATCH "Xcode ([0-9]+\\.[0-9]+)" _ "${_xcodebuild_version_raw}")
        set(_xcode_version "${CMAKE_MATCH_1}")
        message(STATUS "Detected build environment: macOS ${_macos_product_version}, Xcode ${_xcode_version}")
        if(_macos_product_version VERSION_GREATER_EQUAL "26.5"
           AND _xcode_version VERSION_GREATER_EQUAL "26.5")
            set(MACOS_ICON_COMPOSER_TOOLCHAIN_SUPPORTED ON)
        endif()
    endif()

    if(NOT DEFINED MACOS_USE_ICON_COMPOSER)
        if((APPLICATION_NAME STREQUAL "Nextcloud" OR NEXTCLOUD_DEV)
           AND EXISTS "${CMAKE_SOURCE_DIR}/theme/colored/AppIcon.icon/icon.json"
           AND MACOS_ICON_COMPOSER_TOOLCHAIN_SUPPORTED)
            set(MACOS_USE_ICON_COMPOSER ON)
            message(STATUS "Using Icon Composer (.icon) format for the macOS app icon.")
        else()
            set(MACOS_USE_ICON_COMPOSER OFF)
        endif()
    endif()

    if(NOT MACOS_USE_ICON_COMPOSER)
        message(STATUS "macOS app icon: using legacy ECM .icns pipeline.")
        # Restore the macOS-specific (squircle) icon for the default builds so the
        # legacy pipeline emits Nextcloud-macOS.icns rather than the generic logo.
        # Branded builds keep their own ${APPLICATION_ICON_NAME}-icon.svg.
        if((APPLICATION_NAME STREQUAL "Nextcloud" OR NEXTCLOUD_DEV)
           AND EXISTS "${CMAKE_SOURCE_DIR}/theme/colored/Nextcloud-macOS-icon.svg")
            set(APPLICATION_ICON_NAME "Nextcloud-macOS")
            message(STATUS "Using macOS-specific application icon: ${APPLICATION_ICON_NAME}")
        endif()
    endif()
endif()

set( APPLICATION_ICON_SET   "SVG" )
set( APPLICATION_SERVER_URL "https://portal.xeniacloud.eu" CACHE STRING "URL for the server to use. If entered, the UI field will be pre-filled with it" )
set( APPLICATION_SERVER_URL_ENFORCE ON ) # If set and APPLICATION_SERVER_URL is defined, the server can only connect to the pre-defined URL
set( APPLICATION_REV_DOMAIN "eu.xeniacloud.desktopclient" )
set( APPLICATION_REV_DOMAIN_DBUS "desktopclient.xeniacloud.eu" )
# XEN-143: Krateos B.V.'s Apple team, the one that holds the Developer ID certificate.
# Upstream's NKUJUXUJ3B is Nextcloud GmbH's team; the release workflow refuses to sign
# when this differs from the APPLE_TEAM_ID secret. The app-group identifiers of the
# client and both extensions derive from it.
set( DEVELOPMENT_TEAM "HKHX362RBY" CACHE STRING "Apple Development Team ID" )
set( APPLICATION_VIRTUALFILE_SUFFIX "nextcloud" CACHE STRING "Virtual file suffix (not including the .)")
set( APPLICATION_OCSP_STAPLING_ENABLED OFF )
set( APPLICATION_FORBID_BAD_SSL OFF )

set( LINUX_PACKAGE_SHORTNAME "nextcloud" )
set( LINUX_APPLICATION_ID "${APPLICATION_REV_DOMAIN}.${LINUX_PACKAGE_SHORTNAME}")

set( THEME_CLASS            "NextcloudTheme" )
set( WIN_SETUP_BITMAP_PATH  "${CMAKE_SOURCE_DIR}/admin/win/nsi" )

set( MAC_INSTALLER_BACKGROUND_FILE "${CMAKE_SOURCE_DIR}/admin/osx/installer-background.png" CACHE STRING "The MacOSX installer background image")

# set( THEME_INCLUDE          "${OEM_THEME_DIR}/mytheme.h" )
# set( APPLICATION_LICENSE    "${OEM_THEME_DIR}/license.txt )

## Updater options
# XNT-113: off for Xenia builds. There is no xeniacloud-owned update channel, and
# leaving the updater pointed at updates.nextcloud.org sent install-base telemetry
# to a third party and let a third-party-controlled channel push binaries to
# Xenia-branded clients. With this off the updater is not compiled in at all, so the
# Info settings panel hides its update section (InfoSettings::customizeStyle) and no
# Sparkle framework or its temporary-exception entitlements enter the macOS bundle
# (admin/osx/CMakeLists.txt). Turn back on only together with a signed xeniacloud
# channel.
option( BUILD_UPDATER "Build updater" OFF )

option( WITH_PROVIDERS "Build with providers list" ON )

option( ENFORCE_VIRTUAL_FILES_SYNC_FOLDER "Enforce use of virtual files sync folder when available" OFF )
option( DISABLE_VIRTUAL_FILES_SYNC_FOLDER "Disable use of virtual files sync folder even when available" OFF )

option(ENFORCE_SINGLE_ACCOUNT "Enforce use of a single account in desktop client" OFF)

option( DO_NOT_USE_PROXY "Do not use system wide proxy, instead always do a direct connection to server" OFF )

option( WIN_DISABLE_USERNAME_PREFILL "Do not prefill the Windows user name when creating a new account" OFF )

## Theming options
set(NEXTCLOUD_BACKGROUND_COLOR "#002266" CACHE STRING "Default Nextcloud background color")
set( APPLICATION_WIZARD_HEADER_BACKGROUND_COLOR ${NEXTCLOUD_BACKGROUND_COLOR} CACHE STRING "Hex color of the wizard header background")
set( APPLICATION_WIZARD_HEADER_TITLE_COLOR "#ffffff" CACHE STRING "Hex color of the text in the wizard header")
option( APPLICATION_WIZARD_USE_CUSTOM_LOGO "Use the logo from ':/client/theme/colored/wizard_logo.(png|svg)' else the default application icon is used" ON )

#
## Windows Shell Extensions & MSI - IMPORTANT: Generate new GUIDs for custom builds with "guidgen" or "uuidgen"
#
# Xenia Files values, generated for XEN-304 on 4 Nov 2026. They replace upstream
# Nextcloud's, so a Xenia Files MSI never upgrades or removes an installed
# Nextcloud client (and the other way round), and the shell extensions do not
# collide with Nextcloud's in the registry.
# WIN_MSI_UPGRADE_CODE must NEVER change once a Xenia Files MSI has shipped:
# Windows Installer uses it to find the installed copy to upgrade.
#
if(WIN32)
    # Context Menu
    set( WIN_SHELLEXT_CONTEXT_MENU_GUID      "{F6819FB9-0257-4A7F-995E-CD831E29F5B7}" )

    # Overlays
    set( WIN_SHELLEXT_OVERLAY_GUID_ERROR     "{BF3D2A2E-BB57-4E8C-8F13-E4E9D56DC8AA}" )
    set( WIN_SHELLEXT_OVERLAY_GUID_OK        "{BBBA93E8-9907-49F8-B5E2-0609961446D5}" )
    set( WIN_SHELLEXT_OVERLAY_GUID_OK_SHARED "{B1619828-D52A-482E-846C-4E93A21303BB}" )
    set( WIN_SHELLEXT_OVERLAY_GUID_SYNC      "{F9A623EE-F1AD-4893-A731-87C0C4B4370F}" )
    set( WIN_SHELLEXT_OVERLAY_GUID_WARNING   "{87AEDBBB-8884-4FB5-B854-D1D621797C09}" )

    # Virtual files (CfApi) shell extension COM IDs. CMakeLists.txt applies these
    # over upstream's values, which it sets after this file is included.
    set( XENIA_CFAPI_SHELLEXT_APPID                      "1D8C5B3A-1397-4E3E-BD63-550CBBDE9DE2" )
    set( XENIA_CFAPI_SHELLEXT_CUSTOM_STATE_HANDLER_CLSID "0E2116A2-70EB-4E3E-89D4-8224CE124F3F" )
    set( XENIA_CFAPI_SHELLEXT_THUMBNAIL_HANDLER_CLSID    "000BBDF5-FBB4-45F7-ACDE-EFE5884384D9" )

    # MSI Upgrade Code (without brackets)
    set( WIN_MSI_UPGRADE_CODE                "DC291C60-54AB-4039-ADB3-9947ACCEF79A" )

    # Windows build options
    option( BUILD_WIN_MSI "Build MSI scripts and helper DLL" OFF )
    option( BUILD_WIN_TOOLS "Build Win32 migration tools" OFF )
endif()

if (APPLE AND CMAKE_OSX_DEPLOYMENT_TARGET VERSION_GREATER_EQUAL 11.0)
    option( BUILD_FILE_PROVIDER_MODULE "Build the macOS virtual files File Provider module" OFF )
endif()
