cmake_minimum_required(VERSION 3.15)
project(rqml_core)

# Default to C++17
if (NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 17)
endif ()

if (CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif ()

find_package(ament_cmake REQUIRED)
find_package(ament_index_cpp REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(qml6_ros2_plugin REQUIRED)
find_package(yaml_cpp_vendor REQUIRED)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt6_add_resources(
  QML_RESOURCES ${CMAKE_CURRENT_SOURCE_DIR}/qml.qrc) # Use absolute path
set(CMAKE_AUTOMOC ON)

set(KDDockWidgets_QT6
  ON
  CACHE BOOL "Use Qt6 for KDDockWidgets")
set(KDDockWidgets_FRONTENDS
  "qtquick"
  CACHE STRING "Frontends to build for KDDockWidgets")
set(KDDockWidgets_EXAMPLES
  OFF
  CACHE BOOL "Build KDDockWidgets examples")

include(FetchContent)
FetchContent_Declare(
  KDDockWidgets
  GIT_REPOSITORY https://github.com/KDAB/KDDockWidgets.git
  GIT_TAG v2.3.0
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/KDDockWidgets)
FetchContent_MakeAvailable(KDDockWidgets)

set(HEADERS src/rqml_plugin.h)

set(SOURCES
  src/config_manager.cpp
  src/plugin_manager.cpp
  src/rqml.cpp
  src/helpers/file_system_watcher.cpp
)

set(APP_ICON_RESOURCE)
if (WIN32)
  # On Windows, we add the .rc file to the executable
  set(APP_ICON_RESOURCE "${CMAKE_CURRENT_SOURCE_DIR}/assets/windows_icon.rc")
endif ()

add_executable(rqml ${HEADERS} ${SOURCES} ${APP_ICON_RESOURCE})
target_sources(rqml PRIVATE ${QML_RESOURCES}) # Ensure resources are included
target_link_libraries(rqml
  PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  KDAB::kddockwidgets
  ament_index_cpp::ament_index_cpp qml6_ros2_plugin::qml6_ros2_plugin yaml-cpp)
target_compile_definitions(rqml PRIVATE
  CMAKE_INSTALL_PREFIX="${CMAKE_INSTALL_PREFIX}"
)
if (NOT ${CMAKE_BUILD_TYPE} STREQUAL "Debug")
  target_compile_definitions(rqml PRIVATE QT_NO_DEBUG_OUTPUT)
endif ()

install(TARGETS rqml RUNTIME DESTINATION bin)
install(DIRECTORY RQml DESTINATION share/${PROJECT_NAME})

install(
  FILES
  ${CMAKE_CURRENT_SOURCE_DIR}/assets/app_icon.svg
  DESTINATION
  share/${PROJECT_NAME}
)

install(
  DIRECTORY config launch
  DESTINATION share/${PROJECT_NAME}
  OPTIONAL)

ament_environment_hooks(register_qml_module.dsv.in)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()

  find_package(Qt6 REQUIRED COMPONENTS QuickTest)

  add_executable(test_rqml_core test/test_rqml_core.cpp)
  target_compile_definitions(test_rqml_core
    PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test"
  )
  target_link_libraries(test_rqml_core
    PRIVATE
    Qt6::QuickTest
    Qt6::Qml
    Qt6::Quick
  )
  set(TEST_RESULT_DIR "${CMAKE_BINARY_DIR}/test_results/${PROJECT_NAME}")
  ament_add_test(
    test_rqml_core
    COMMAND $<TARGET_FILE:test_rqml_core>
        -import "${CMAKE_CURRENT_SOURCE_DIR}"
        -import "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks"
        -junitxml
        -o "${TEST_RESULT_DIR}/test_rqml_core.xml"
    ENV QT_QPA_PLATFORM=offscreen
    RESULT_FILE "${TEST_RESULT_DIR}/test_rqml_core.xml"
    TIMEOUT 300
  )
endif()

ament_package()
