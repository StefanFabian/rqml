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

  add_executable(test_parameter_editor test/test_parameter_editor.cpp)
  target_compile_definitions(test_parameter_editor
    PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/test"
  )
  target_link_libraries(test_parameter_editor
    PRIVATE
    Qt6::QuickTest
    Qt6::Qml
    Qt6::Quick
  )
  set(TEST_RESULT_DIR "${CMAKE_BINARY_DIR}/test_results/${PROJECT_NAME}")
  ament_add_test(
    test_parameter_editor
    COMMAND $<TARGET_FILE:test_parameter_editor>
        -import "${CMAKE_CURRENT_SOURCE_DIR}/test/mocks"
        -import "${CMAKE_CURRENT_SOURCE_DIR}/qml"
        -junitxml
        -o "${TEST_RESULT_DIR}/test_parameter_editor.xml"
    RESULT_FILE "${TEST_RESULT_DIR}/test_parameter_editor.xml"
  )
endif()

ament_package()
