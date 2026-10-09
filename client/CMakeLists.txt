cmake_minimum_required(VERSION 3.25.0 FATAL_ERROR)

set(PROJECT "Dopamine")
project(${PROJECT})

# generate dSYMs for all targets (crash symbolication for TestFlight/App Store)
set(CMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT "dwarf-with-dsym")

set_property(GLOBAL PROPERTY USE_FOLDERS ON)
set_property(GLOBAL PROPERTY AUTOGEN_TARGETS_FOLDER "Autogen")
set_property(GLOBAL PROPERTY AUTOMOC_TARGETS_FOLDER "Autogen")
set_property(GLOBAL PROPERTY PREDEFINED_TARGETS_FOLDER "Autogen")

set(PACKAGES
    Core Gui Network Xml
    RemoteObjects Quick Svg QuickControls2
    Core5Compat Concurrent LinguistTools ShaderTools
)

execute_process(
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
  COMMAND git rev-parse --short HEAD
  OUTPUT_VARIABLE GIT_COMMIT_HASH
  OUTPUT_STRIP_TRAILING_WHITESPACE
)

add_definitions(-DGIT_COMMIT_HASH="${GIT_COMMIT_HASH}")

# The gateway the app talks to is a build input, not part of the source:
# its URL (LODESTAR_GATEWAY_URL, optionally more tried when it does not answer:
# LODESTAR_GATEWAY_FALLBACK_URL, one URL or several separated by commas) and its
# RSA public key, client/agw_public.pem or the file given in LODESTAR_GATEWAY_KEY.
# All can come from the environment.
set(LODESTAR_GATEWAY_URL "$ENV{LODESTAR_GATEWAY_URL}" CACHE STRING "Gateway URL, e.g. https://gw.example.com/")
set(LODESTAR_GATEWAY_FALLBACK_URL "$ENV{LODESTAR_GATEWAY_FALLBACK_URL}" CACHE STRING "Second gateway URL (optional)")
set(LODESTAR_GATEWAY_KEY "$ENV{LODESTAR_GATEWAY_KEY}" CACHE FILEPATH "Gateway RSA public key (PEM)")
set(LODESTAR_GATEWAY_CA "$ENV{LODESTAR_GATEWAY_CA}" CACHE FILEPATH "Gateway certificate authority (PEM, optional)")
# what the environment gives wins over what a reused build directory remembers:
# a cache variable is not set again otherwise, and a build for another relay
# would silently carry the old one (the Android build passes these this way)
foreach(var LODESTAR_GATEWAY_URL LODESTAR_GATEWAY_FALLBACK_URL LODESTAR_GATEWAY_KEY LODESTAR_GATEWAY_CA)
    if(NOT "$ENV{${var}}" STREQUAL "" AND NOT "$ENV{${var}}" STREQUAL "${${var}}")
        get_property(doc CACHE ${var} PROPERTY HELPSTRING)
        get_property(type CACHE ${var} PROPERTY TYPE)
        set(${var} "$ENV{${var}}" CACHE ${type} "${doc}" FORCE)
    endif()
endforeach()
if(LODESTAR_GATEWAY_URL STREQUAL "")
    message(FATAL_ERROR "Set LODESTAR_GATEWAY_URL to the gateway URL")
endif()
if(LODESTAR_GATEWAY_FALLBACK_URL STREQUAL "")
    set(LODESTAR_GATEWAY_FALLBACK_URL "${LODESTAR_GATEWAY_URL}")
endif()
add_definitions(-DLODESTAR_GATEWAY_URL="${LODESTAR_GATEWAY_URL}")
add_definitions(-DLODESTAR_GATEWAY_FALLBACK_URL="${LODESTAR_GATEWAY_FALLBACK_URL}")
if(NOT LODESTAR_GATEWAY_KEY STREQUAL "")
    configure_file("${LODESTAR_GATEWAY_KEY}" "${CMAKE_CURRENT_SOURCE_DIR}/agw_public.pem" COPYONLY)
endif()
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/agw_public.pem")
    message(FATAL_ERROR "Put the gateway's RSA public key at client/agw_public.pem or set LODESTAR_GATEWAY_KEY")
endif()
# The gateway's own certificate authority (LODESTAR_GATEWAY_CA, PEM): HTTPS to
# its relays is trusted by it alone. Without one the file is empty and an
# https gateway URL is checked against the system's authorities.
if(NOT LODESTAR_GATEWAY_CA STREQUAL "")
    configure_file("${LODESTAR_GATEWAY_CA}" "${CMAKE_CURRENT_SOURCE_DIR}/gateway_ca.pem" COPYONLY)
elseif(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/gateway_ca.pem")
    file(WRITE "${CMAKE_CURRENT_SOURCE_DIR}/gateway_ca.pem" "")
endif()

add_definitions(-DPROD_S3_ENDPOINT="$ENV{PROD_S3_ENDPOINT}")
add_definitions(-DDEV_AGW_ENDPOINT="$ENV{DEV_AGW_ENDPOINT}")
add_definitions(-DDEV_S3_ENDPOINT="$ENV{DEV_S3_ENDPOINT}")

add_definitions(-DFREE_V2_ENDPOINT="$ENV{FREE_V2_ENDPOINT}")
add_definitions(-DPREM_V1_ENDPOINT="$ENV{PREM_V1_ENDPOINT}")

if(WIN32 OR (APPLE AND NOT IOS) OR (LINUX AND NOT ANDROID))
    set(PACKAGES ${PACKAGES} Widgets)
endif()

find_package(Qt6 REQUIRED COMPONENTS ${PACKAGES})

set(LIBS ${LIBS}
    Qt6::Core Qt6::Gui
    Qt6::Network Qt6::Xml Qt6::RemoteObjects
    Qt6::Quick Qt6::Svg Qt6::QuickControls2
    Qt6::Core5Compat Qt6::Concurrent
)

if(WIN32 OR (APPLE AND NOT IOS) OR (LINUX AND NOT ANDROID))
    set(LIBS ${LIBS} Qt6::Widgets)
endif()

qt_standard_project_setup()
qt_add_executable(${PROJECT} MANUAL_FINALIZATION)

if(WIN32)
    # qt_add_executable lost the WIN32 flag somewhere along MANUAL_FINALIZATION —
    # the shipped exe came out as console subsystem and spawned a terminal window
    set_target_properties(${PROJECT} PROPERTIES WIN32_EXECUTABLE ON)
    target_link_options(${PROJECT} PRIVATE "/ENTRY:mainCRTStartup")
    # product name on Windows; the target keeps its upstream name because the
    # Apple builds derive the generated Swift header (Dopamine-Swift.h) from it
    set_target_properties(${PROJECT} PROPERTIES OUTPUT_NAME "Lodestar")
endif()
target_include_directories(${PROJECT} PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>
)

if(WIN32 OR (APPLE AND NOT IOS AND NOT MACOS_NE) OR (LINUX AND NOT ANDROID))
    qt_add_repc_replicas(${PROJECT} ${CMAKE_CURRENT_LIST_DIR}/../ipc/ipc_interface.rep)
    qt_add_repc_replicas(${PROJECT} ${CMAKE_CURRENT_LIST_DIR}/../ipc/ipc_process_interface.rep)
endif()

qt6_add_resources(QRC ${QRC} ${CMAKE_CURRENT_LIST_DIR}/resources.qrc)

# connect button's night sky (qrc:/shaders/nightsky.frag.qsb, all RHI backends)
qt_add_shaders(${PROJECT} "shaders"
    PREFIX "/"
    FILES shaders/nightsky.frag
)

# -- i18n begin
set(CMAKE_AUTORCC ON)

set(DOPAMINE_TS_FILES
    ${CMAKE_CURRENT_LIST_DIR}/translations/dopamine_en_US.ts
    ${CMAKE_CURRENT_LIST_DIR}/translations/dopamine_ru_RU.ts
    ${CMAKE_CURRENT_LIST_DIR}/translations/dopamine_uk_UA.ts
)

file(GLOB_RECURSE DOPAMINE_TS_SOURCES *.qrc *.cpp *.h *.ui)
list(FILTER DOPAMINE_TS_SOURCES EXCLUDE REGEX "qtgamepad/examples")

qt_create_translation(DOPAMINE_QM_FILES ${DOPAMINE_TS_SOURCES} ${DOPAMINE_TS_FILES})

set(QM_FILE_LIST "")
foreach(FILE ${DOPAMINE_QM_FILES})
    get_filename_component(QM_FILE_NAME ${FILE} NAME)
    list(APPEND QM_FILE_LIST "<file>${QM_FILE_NAME}</file>")
endforeach()
string(REPLACE ";" "" QM_FILE_LIST ${QM_FILE_LIST})

configure_file(${CMAKE_CURRENT_LIST_DIR}/translations/translations.qrc.in ${CMAKE_CURRENT_BINARY_DIR}/translations.qrc)
qt6_add_resources(QRC ${I18NQRC} ${CMAKE_CURRENT_BINARY_DIR}/translations.qrc)
# -- i18n end

set(IS_CI ${CI})
if(IS_CI)
    message("Detected CI env")
    find_program(CCACHE "ccache")
    if(CCACHE)
        set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${CCACHE}")
    endif()
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmake/3rdparty.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/cmake/sources.cmake)

include_directories(
    ${CMAKE_CURRENT_LIST_DIR}/../ipc
    ${CMAKE_CURRENT_LIST_DIR}/../common/logger
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
)

if(MACOS_NE)
    message("MACOS_NE is ON")
    add_definitions(-DQ_OS_MAC)
    add_definitions(-DMACOS_NE)
    message("Add macros for MacOS Network Extension")
else()
    message("MACOS_NE is OFF")
endif()

include_directories(mozilla)
include_directories(mozilla/shared)
include_directories(mozilla/models)

configure_file(${CMAKE_CURRENT_LIST_DIR}/../version.h.in ${CMAKE_CURRENT_BINARY_DIR}/version.h)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_definitions(${PROJECT} PRIVATE "MZ_DEBUG")
endif()

if(WIN32)
    configure_file(
        ${CMAKE_CURRENT_LIST_DIR}/platforms/windows/dopamine.rc.in
        ${CMAKE_CURRENT_BINARY_DIR}/dopamine.rc
    )

    set(LIBS ${LIBS}
        user32
        rasapi32
        shlwapi
        iphlpapi
        ws2_32
        gdi32
        crypt32
    )

    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup")
endif()

if(APPLE)
    cmake_policy(SET CMP0099 NEW)
    cmake_policy(SET CMP0114 NEW)

    if(NOT BUILD_OSX_APP_IDENTIFIER)
        set(BUILD_OSX_APP_IDENTIFIER org.frkn.dopamine CACHE STRING "OSX Application identifier")
    endif()
    if(NOT BUILD_IOS_APP_IDENTIFIER)
        set(BUILD_IOS_APP_IDENTIFIER org.frkn.dopamine CACHE STRING "iOS Application identifier")
    endif()
    if(NOT BUILD_IOS_GROUP_IDENTIFIER)
        set(BUILD_IOS_GROUP_IDENTIFIER group.org.frkn.dopamine CACHE STRING "iOS Group identifier")
    endif()
    if(NOT BUILD_VPN_DEVELOPMENT_TEAM)
        set(BUILD_VPN_DEVELOPMENT_TEAM 455SJ7P6J3 CACHE STRING "FRKN Crew")
    endif()

    set(CMAKE_XCODE_GENERATE_SCHEME FALSE)
    set(CMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ${BUILD_VPN_DEVELOPMENT_TEAM})
    set(CMAKE_XCODE_ATTRIBUTE_GROUP_ID_IOS ${BUILD_IOS_GROUP_IDENTIFIER})
endif()

if(LINUX AND NOT ANDROID)
    set(LIBS ${LIBS} -static-libstdc++ -static-libgcc -ldl)
    link_directories(${CMAKE_CURRENT_LIST_DIR}/platforms/linux)
endif()

if(WIN32 OR (APPLE AND NOT IOS AND NOT MACOS_NE) OR (LINUX AND NOT ANDROID))
    add_compile_definitions(AMNEZIA_DESKTOP)
endif()

if(ANDROID)
    include(cmake/android.cmake)
endif()

if(IOS)
    include(cmake/ios.cmake)
    include(cmake/ios-arch-fixup.cmake)
elseif(APPLE AND MACOS_NE)
    include(cmake/macos_ne.cmake)
elseif(APPLE)
    include(cmake/osxtools.cmake)
    include(cmake/macos.cmake)
endif()

target_link_libraries(${PROJECT} PRIVATE ${LIBS})
target_compile_definitions(${PROJECT} PRIVATE "MZ_$<UPPER_CASE:${MZ_PLATFORM_NAME}>")

# deploy artifacts required to run the application to the debug build folder
if(WIN32)
    if("${CMAKE_SIZEOF_VOID_P}" STREQUAL "8")
        set(DEPLOY_PLATFORM_PATH "windows/x64")
    else()
        set(DEPLOY_PLATFORM_PATH "windows/x32")
    endif()
elseif(LINUX)
    set(DEPLOY_PLATFORM_PATH "linux/client")
elseif(APPLE AND NOT IOS)
    set(DEPLOY_PLATFORM_PATH "macos")
endif()

if(NOT IOS AND NOT ANDROID AND NOT MACOS_NE)
    add_custom_command(
        TARGET ${PROJECT} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E $<IF:$<CONFIG:Debug>,copy_directory,true>
        ${CMAKE_SOURCE_DIR}/deploy/data/${DEPLOY_PLATFORM_PATH}
        $<TARGET_FILE_DIR:${PROJECT}>
        COMMAND_EXPAND_LISTS
    )
    add_custom_command(
        TARGET ${PROJECT} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E $<IF:$<CONFIG:Debug>,copy_directory,true>
        ${CMAKE_SOURCE_DIR}/client/3rd-prebuilt/deploy-prebuilt/${DEPLOY_PLATFORM_PATH}
        $<TARGET_FILE_DIR:${PROJECT}>
        COMMAND_EXPAND_LISTS
    )
endif()

target_sources(${PROJECT} PRIVATE ${SOURCES} ${HEADERS} ${RESOURCES} ${QRC} ${I18NQRC})

# Finalize the executable so Qt can gather/deploy QML modules and plugins correctly (Android needs this).
if(COMMAND qt_import_qml_plugins)
    qt_import_qml_plugins(${PROJECT})
endif()
if(COMMAND qt_finalize_executable)
    qt_finalize_executable(${PROJECT})
else()
    qt_finalize_target(${PROJECT})
endif()
