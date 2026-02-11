#!/usr/bin/env python3
#
# IRIS Source Code - Custom module
# IrisE01Processor: processor module triggered on evidence creation.
#
# This module subscribes to the `on_postload_evidence_create` hook. When a new
# piece of evidence is registered, it attempts to resolve the associated
# datastore file path (for large images such as E01) and spawns a background
# process to run a user-provided script against that path.
#
# The script path and behaviour are fully controlled via the module
# configuration in the IRIS UI.

import os
import shlex
import subprocess
from typing import Iterable, List, Optional

import iris_interface.IrisInterfaceStatus as InterfaceStatus
from iris_interface.IrisModuleInterface import IrisModuleInterface, IrisModuleTypes

import iris_e01_processor.IrisE01ProcessorConfig as interface_conf

from app import app, db
from app.iris_engine.utils.common import build_upload_path
from app.models.cases import Cases
from app.models.models import CaseReceivedFile, Client, DataStoreFile


class IrisE01Processor(IrisModuleInterface):
    """
    Processor module that reacts to evidence creation and launches an external
    script to process large images (e.g. E01) outside the web front-end.
    """

    # Static metadata picked up by IRIS
    _module_name = interface_conf.module_name
    _module_description = interface_conf.module_description
    _interface_version = interface_conf.interface_version
    _module_version = interface_conf.module_version
    _pipeline_support = interface_conf.pipeline_support
    _pipeline_info = interface_conf.pipeline_info
    _module_configuration = interface_conf.module_configuration
    _module_type = interface_conf.module_type

    def register_hooks(self, module_id: int):
        """
        Called by IRIS when (re)registering the module so it can subscribe to
        hooks. We register to `on_postload_evidence_create` so we are notified
        whenever new evidence is committed to the database.
        """

        status = self.register_to_hook(
            module_id,
            iris_hook_name="on_postload_evidence_create",
            run_asynchronously=True,
        )

        if status.is_failure():
            # Log the failure; IRIS will record it in the module logs.
            self.log.error(status.get_message())
        else:
            self.log.info(
                "IrisE01Processor successfully subscribed to on_postload_evidence_create"
            )

        return status

    # --------------------------------------------------------------------- #
    # Hook handling
    # --------------------------------------------------------------------- #

    def hooks_handler(self, hook_name: str, hook_ui_name: str, data: Iterable):
        """
        Called by IRIS each time a hook this module is subscribed to is
        triggered.

        :param hook_name: Name of the hook that fired.
        :param hook_ui_name: Manual hook UI name (unused here).
        :param data: List of SQLAlchemy objects, as prepared by IRIS.
        :return: IrisInterfaceStatus object.
        """

        try:
            conf = self.module_dict_conf  # Refresh configuration on each call
        except Exception:
            # Fall back to whatever configuration we currently have
            conf = getattr(self, "_dict_conf", {}) or {}

        enabled = bool(conf.get("enabled", True))
        if not enabled:
            # Module is disabled via configuration; just return the original data.
            return InterfaceStatus.I2Success(data=data, logs=list(self.message_queue))

        # We only handle evidence creation hooks here. For any other hook, we
        # simply return the data untouched.
        if hook_name != "on_postload_evidence_create":
            return InterfaceStatus.I2Success(data=data, logs=list(self.message_queue))

        script_path = conf.get("e01_script_path")
        extra_args_raw = conf.get("e01_script_extra_args") or ""
        log_debug = bool(conf.get("log_debug", False))

        if not script_path:
            self.log.error(
                "IrisE01Processor: e01_script_path is not configured; "
                "skipping evidence processing."
            )
            return InterfaceStatus.I2Error(
                message="e01_script_path not configured", logs=list(self.message_queue)
            )

        evidences: List[CaseReceivedFile] = []
        if isinstance(data, list):
            evidences = [ev for ev in data if isinstance(ev, CaseReceivedFile)]
        elif isinstance(data, CaseReceivedFile):
            evidences = [data]

        if not evidences:
            if log_debug:
                self.log.debug(
                    f"IrisE01Processor: hook {hook_name} received no CaseReceivedFile instances."
                )
            return InterfaceStatus.I2Success(data=data, logs=list(self.message_queue))

        for evidence in evidences:
            try:
                e01_path = self._resolve_evidence_path(evidence)
                if not e01_path:
                    # Nothing to do if we cannot resolve a local path (for example,
                    # evidence not backed by datastore).
                    self.log.warning(
                        f"IrisE01Processor: unable to resolve local path for "
                        f"evidence id={evidence.id}, case_id={evidence.case_id}"
                    )
                    continue

                output_dir = self._compute_output_dir(evidence)

                if log_debug:
                    self.log.debug(
                        "IrisE01Processor: launching script '%s' for evidence id=%s, "
                        "case_id=%s, e01_path='%s', output_dir='%s'",
                        script_path,
                        evidence.id,
                        evidence.case_id,
                        e01_path,
                        output_dir or "",
                    )

                self._launch_processing_script(
                    script_path=script_path,
                    extra_args_raw=extra_args_raw,
                    evidence=evidence,
                    e01_path=e01_path,
                    output_dir=output_dir,
                )
            except Exception as e:
                # Keep going for other evidences even if one fails.
                self.log.exception(
                    "IrisE01Processor: error while handling evidence id=%s: %s",
                    getattr(evidence, "id", "unknown"),
                    str(e),
                )

        # Always return the original data back to IRIS so the hook chain can
        # continue normally.
        return InterfaceStatus.I2Success(data=data, logs=list(self.message_queue))

    # ------------------------------------------------------------------ #
    # Internal helpers
    # ------------------------------------------------------------------ #

    def _resolve_evidence_path(self, evidence: CaseReceivedFile) -> Optional[str]:
        """
        Given a CaseReceivedFile, attempt to resolve the corresponding
        DataStoreFile.local path using the evidence hash and case id.
        """
        if not evidence.file_hash or not evidence.case_id:
            return None

        dsf = (
            DataStoreFile.query.filter(
                DataStoreFile.file_case_id == evidence.case_id,
                DataStoreFile.file_sha256 == evidence.file_hash,
            )
            .order_by(DataStoreFile.file_date_added.desc())
            .first()
        )

        if not dsf:
            self.log.warning(
                "IrisE01Processor: no DataStoreFile found for evidence id=%s "
                "case_id=%s sha256=%s",
                evidence.id,
                evidence.case_id,
                evidence.file_hash,
            )
            return None

        return dsf.file_local_name

    def _compute_output_dir(self, evidence: CaseReceivedFile) -> Optional[str]:
        """
        Compute a per-case output directory for this module under the standard
        UPLOADED_PATH root using build_upload_path. This is optional but
        provides a consistent location for artifacts like timelines, logs, etc.
        """
        try:
            case: Cases = evidence.case
            client: Optional[Client] = case.client if case else None

            case_customer = client.name if client else None
            case_name = case.name if case else None

            if not case_customer or not case_name:
                return None

            # Use this module name to generate a dedicated subdirectory.
            output_dir = build_upload_path(
                case_customer=case_customer,
                case_name=case_name,
                module=self._module_name,
                create=True,
            )

            return output_dir
        except Exception as e:
            self.log.exception(
                "IrisE01Processor: failed to compute output directory for "
                "evidence id=%s: %s",
                getattr(evidence, "id", "unknown"),
                str(e),
            )
            return None

    def _launch_processing_script(
        self,
        script_path: str,
        extra_args_raw: str,
        evidence: CaseReceivedFile,
        e01_path: str,
        output_dir: Optional[str],
    ) -> None:
        """
        Spawn the user-defined processing script in the background.

        The script receives:
          - the E01 path as first positional argument
          - any extra CLI args configured in `e01_script_extra_args`
        and the following environment variables:
          - IRIS_CASE_ID
          - IRIS_EVIDENCE_ID
          - IRIS_E01_PATH
          - IRIS_E01_OUTPUT_DIR
          - IRIS_MODULE_NAME
        """
        args: List[str] = [script_path, e01_path]
        extra_args: List[str] = []

        if extra_args_raw:
            try:
                extra_args = shlex.split(extra_args_raw)
            except ValueError:
                # Malformed extra args; log and ignore.
                self.log.error(
                    "IrisE01Processor: failed to parse e01_script_extra_args '%s'; "
                    "ignoring extra args.",
                    extra_args_raw,
                )

        args.extend(extra_args)

        env = os.environ.copy()
        env.update(
            {
                "IRIS_CASE_ID": str(evidence.case_id),
                "IRIS_EVIDENCE_ID": str(evidence.id),
                "IRIS_E01_PATH": e01_path,
                "IRIS_E01_OUTPUT_DIR": output_dir or "",
                "IRIS_MODULE_NAME": self._module_name,
            }
        )

        # Use Popen to avoid blocking the Celery worker; errors will be visible
        # in the container logs or handled by the script itself.
        try:
            subprocess.Popen(
                args,
                env=env,
                cwd=output_dir or app.config.get("UPLOADED_PATH", None),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            self.log.error(
                "IrisE01Processor: script '%s' not found or not executable.", script_path
            )
        except Exception as e:
            self.log.exception(
                "IrisE01Processor: failed to launch script '%s': %s",
                script_path,
                str(e),
            )

