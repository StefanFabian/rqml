.pragma library

//! Suffixes of the parameter, logger and type description services every node offers.
const DEFAULT_SERVICE_SUFFIXES = ["/describe_parameters", "/get_logger_levels", "/get_parameter_types", "/get_parameters", "/get_type_description", "/list_parameters", "/set_logger_levels", "/set_parameters", "/set_parameters_atomically"];

//! Topics every node connects to by default.
const DEFAULT_TOPICS = ["/parameter_events", "/rosout"];

/**
 * Whether the topic or service is one ROS creates internally to implement an action.
 */
function isActionInternal(name) {
    return name.includes("/_action/");
}

/**
 * Whether the service is one of the parameter, logger or type description services every node offers.
 */
function isDefaultService(name) {
    return DEFAULT_SERVICE_SUFFIXES.some(suffix => name.endsWith(suffix));
}

/**
 * Whether the topic is one of the parameter event or log topics every node connects to.
 */
function isDefaultTopic(name) {
    return DEFAULT_TOPICS.includes(name);
}

/**
 * Returns the service names without action internals and, unless showDefault is set, without default services.
 */
function filterServices(names, showDefault) {
    return names.filter(name => !isActionInternal(name) && (showDefault || !isDefaultService(name)));
}
