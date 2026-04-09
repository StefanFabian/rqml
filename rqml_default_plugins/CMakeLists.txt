cmake_minimum_required(VERSION 3.15)
project(rqml_default_plugins)

find_package(ament_cmake REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Quick Multimedia)
set(CMAKE_AUTOMOC ON)

add_subdirectory(RQml/DefaultPlugins)

install(DIRECTORY qml DESTINATION share/${PROJECT_NAME})
ament_index_register_resource(rqml_plugin CONTENT_FILE rqml_plugins.yaml.in)

ament_environment_hooks(register_qml_module.dsv.in)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  ament_lint_auto_find_test_dependencies()

  find_package(Qt6 REQUIRED COMPONENTS QuickTest)
  find_package(qml6_ros2_plugin REQUIRED)

  # Build mock Ros2 module in the build tree.
  # Overrides Ros2 singleton, Subscription, and ImageTransportSubscription
  # with QML files. Real C++ types (e.g. MessageItemModel) are registered in the
  # test harness (test_plugins.cpp) by linking against qml6_ros2_plugin.
  set(MOCK_ROS2_DIR "${CMAKE_CURRENT_BINARY_DIR}/test_mocks/Ros2")
  file(MAKE_DIRECTORY "${MOCK_ROS2_DIR}")
  file(GLOB _MOCK_FILES "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks/Ros2/*")
  foreach(mock_file ${_MOCK_FILES})
    get_filename_component(_fname "${mock_file}" NAME)
    file(CREATE_LINK
            "${mock_file}" "${MOCK_ROS2_DIR}/${_fname}"
            COPY_ON_ERROR SYMBOLIC)
  endforeach()

  set(MOCK_DIALOGS_DIR "${CMAKE_CURRENT_BINARY_DIR}/test_mocks/QtQuick")
  file(MAKE_DIRECTORY "${MOCK_DIALOGS_DIR}")
  file(CREATE_LINK
          "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks/QtQuick/Dialogs"
          "${MOCK_DIALOGS_DIR}/Dialogs"
          COPY_ON_ERROR SYMBOLIC)

  add_executable(test_plugins
    test/test_plugins.cpp
    test/mock_ros2.cpp
    test/mock_classes.cpp
  )
  target_compile_definitions(test_plugins
    PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test"
  )
  target_link_libraries(test_plugins
    PRIVATE
    Qt6::QuickTest
    Qt6::Qml
    Qt6::Quick
    qml6_ros2_plugin::qml6_ros2_plugin
  )
  set(TEST_RESULT_DIR "${CMAKE_BINARY_DIR}/test_results/${PROJECT_NAME}")
  ament_add_test(
    test_plugins
    COMMAND $<TARGET_FILE:test_plugins>
        -import "${CMAKE_CURRENT_BINARY_DIR}/test_mocks"
        -import "${CMAKE_CURRENT_SOURCE_DIR}/qml"
        -junitxml
        -o "${TEST_RESULT_DIR}/test_plugins.xml"
    ENV QT_QPA_PLATFORM=offscreen
    RESULT_FILE "${TEST_RESULT_DIR}/test_plugins.xml"
    TIMEOUT 300
  )
endif()

ament_package()
