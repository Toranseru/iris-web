#!/usr/bin/env python3
#
# IRIS Source Code - Custom module
# Configuration for the IrisE01Processor module.
#
# This follows the same pattern as the official DFIR-IRIS modules
# (see iris_evtx, iris_vt_module, etc.).

from iris_interface.IrisModuleInterface import IrisModuleTypes


# Human-readable name shown in Manage > Modules
module_name = "iris_e01_processor"

# Description shown in the module configuration UI
module_description = (
    "Processor module that reacts when new evidence is registered and "
    "launches an external script to process E01 images (e.g. Plaso, KAPE)."
)

# Must match the interface version of the installed iris_interface package
# (see dependencies/iris_interface-1.2.0-*.whl)
interface_version = "1.2.0"

# Arbitrary module version
module_version = "0.1.0"

# This is a processor module (hook-driven), not a pipeline module
module_type = IrisModuleTypes.module_processor

# Processor modules do not expose pipelines
pipeline_support = False
pipeline_info = {}

# Configuration exposed in the IRIS UI
#
# Administrators can set where the E01 processing script lives inside the
# container, how to call it, and whether to enable the module.
module_configuration = [
    {
        "param_name": "enabled",
        "param_human_name": "Enable E01 processor",
        "param_description": (
            "If false, the module will ignore hooks and not launch any processing."
        ),
        "default": True,
        "mandatory": True,
        "type": "bool",
    },
    {
        "param_name": "e01_script_path",
        "param_human_name": "E01 processing script path",
        "param_description": (
            "Absolute path inside the worker/webapp container to the script that will "
            "process the E01 image. The script must be executable and reachable from "
            "the IRIS process (for example: /opt/iris/e01_processing/process_e01.sh)."
        ),
        "default": "/opt/iris/e01_processing/process_e01.sh",
        "mandatory": True,
        "type": "string",
    },
    {
        "param_name": "e01_script_extra_args",
        "param_human_name": "Extra arguments for the script",
        "param_description": (
            "Optional additional CLI arguments passed to the script. The E01 file path "
            "will always be provided as the first positional argument. "
            "Use this field for flags or other fixed parameters."
        ),
        "default": "",
        "mandatory": False,
        "type": "string",
    },
    {
        "param_name": "log_debug",
        "param_human_name": "Verbose logging",
        "param_description": (
            "If true, the module will log detailed information about evidence resolution "
            "and command execution to the module log."
        ),
        "default": False,
        "mandatory": False,
        "type": "bool",
    },
]

