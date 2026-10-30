enable_language(CXX)
find_package(SoapySDR CONFIG QUIET)
if(SoapySDR_FOUND)
    SOAPY_SDR_MODULE_UTIL(
        TARGET birriasdrSupport
        SOURCES BirriaSDR.cpp
        LIBRARIES birriasdr)
else()
    # MSYS2's SoapySDR package ships pkg-config only (no CMake config).
    # Match what SOAPY_SDR_MODULE_UTIL provides: a plain MODULE target with
    # no lib prefix, linked against SoapySDR. The ABI version for the
    # install path comes from the installed Version.h.
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(SOAPY_SDR IMPORTED_TARGET SoapySDR)
    pkg_get_variable(SOAPY_SDR_INCLUDE_DIR SoapySDR includedir)
    file(STRINGS "${SOAPY_SDR_INCLUDE_DIR}/SoapySDR/Version.h" SOAPY_SDR_ABI_LINE
         REGEX "^#define SOAPY_SDR_ABI_VERSION")
    string(REGEX REPLACE ".*\"([^\"]+)\".*" "\\1" SOAPY_SDR_ABI_VERSION "${SOAPY_SDR_ABI_LINE}")
    add_library(birriasdrSupport MODULE BirriaSDR.cpp)
    target_link_libraries(birriasdrSupport PRIVATE birriasdr PkgConfig::SOAPY_SDR)
    set_target_properties(birriasdrSupport PROPERTIES PREFIX "")
endif()
set_target_properties(birriasdrSupport PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON CXX_EXTENSIONS OFF)

# Modules install to <libdir>/SoapySDR/modules<ABI>; find libbirriasdr two levels up.
file(RELATIVE_PATH BIRRIA_MODULE_TO_LIB
    "${CMAKE_INSTALL_FULL_LIBDIR}/SoapySDR/modules${SOAPY_SDR_ABI_VERSION}" "${CMAKE_INSTALL_FULL_LIBDIR}")
if(APPLE)
    set_target_properties(birriasdrSupport PROPERTIES INSTALL_RPATH "@loader_path/${BIRRIA_MODULE_TO_LIB}")
elseif(UNIX)
    set_target_properties(birriasdrSupport PROPERTIES INSTALL_RPATH "$ORIGIN/${BIRRIA_MODULE_TO_LIB}")
endif()

if(BUILD_TESTING)
    add_executable(test_soapy_bands tests/test_bands.cpp)
    target_include_directories(test_soapy_bands PRIVATE ${PROJECT_SOURCE_DIR}/include)
    set_target_properties(test_soapy_bands PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON CXX_EXTENSIONS OFF)
    add_test(NAME soapy_bands COMMAND test_soapy_bands)
endif()

if(BUILD_TESTING)
    add_executable(test_soapy_gain ../tests/test_soapy_gain.cpp $<TARGET_OBJECTS:test_soapy_gain_controls>)
    # SoapySDR arrives either as a CMake config (SoapySDR_* vars) or, on this
    # port's MSYS2 pkg-config fallback, as PkgConfig::SOAPY_SDR.
    target_include_directories(test_soapy_gain PRIVATE ../include ../src ${LIBUSB_INCLUDE_DIR}
        ${SoapySDR_INCLUDE_DIRS} ${SOAPY_SDR_INCLUDE_DIR})
    target_compile_definitions(test_soapy_gain PRIVATE _POSIX_C_SOURCE=200809L)
    # Pin C++17 explicitly: GCC 16's newer default pulls <ciso646> warnings
    # through the SoapySDR headers, and mixed c_std/cxx_std features did not
    # emit the -std flag here.
    set_target_properties(test_soapy_gain PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON CXX_EXTENSIONS OFF)
    if(TARGET PkgConfig::SOAPY_SDR)
        target_link_libraries(test_soapy_gain PRIVATE PkgConfig::SOAPY_SDR)
    else()
        target_link_libraries(test_soapy_gain PRIVATE ${SoapySDR_LIBRARIES})
    endif()
    target_link_libraries(test_soapy_gain PRIVATE Threads::Threads)
    add_test(NAME soapy_gain_commit COMMAND test_soapy_gain)
endif()
