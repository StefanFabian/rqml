cmake_minimum_required(VERSION 3.15)
project(rqml_default_plugins)

find_package(ament_cmake REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Quick Multimedia)
set(CMAKE_AUTOMOC ON)

add_subdirectory(RQml/DefaultPlugins)

install(DIRECTORY qml DESTINATION share/${PROJECT_NAME})
ament_index_register_resource(rqml_plugin CONTENT_FILE rqml_plugins.yaml.in)

ament_environment_hooks(register_qml_module.dsv.in)

ament_package()
