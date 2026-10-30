qt_add_qml_module(rqml_default_plugins_cpp
    URI RQml.DefaultPlugins
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    SOURCES
        depth_image_processor.cpp
        depth_image_processor.hpp
    PLUGIN_TARGET rqml_default_plugins_cpp
)
target_link_libraries(rqml_default_plugins_cpp PRIVATE Qt6::Multimedia)

install(TARGETS rqml_default_plugins_cpp
    EXPORT rqml_default_pluginsTargets
    DESTINATION share/${PROJECT_NAME}/RQml/DefaultPlugins
)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/qmldir
    DESTINATION share/${PROJECT_NAME}/RQml/DefaultPlugins
)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/rqml_default_plugins_cpp.qmltypes
    DESTINATION share/${PROJECT_NAME}/RQml/DefaultPlugins
    OPTIONAL
)
