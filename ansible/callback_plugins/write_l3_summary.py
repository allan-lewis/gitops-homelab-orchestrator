# write_l3_summary.py
# Modern Ansible callback plugin for writing an L3 summary JSON file.

from __future__ import absolute_import, division, print_function
__metaclass__ = type

import json
import os
from datetime import datetime

from ansible.plugins.callback import CallbackBase

DOCUMENTATION = '''
callback: write_l3_summary
type: aggregate
short_description: Write an L3 summary JSON file
version_added: "2.15"
description:
  - Writes a summary JSON file at artifacts/l3/l3_summary.json
'''

class CallbackModule(CallbackBase):
    """
    Aggregate callback plugin that writes L3 summary JSON at the end of play.
    """

    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'write_l3_summary'

    def __init__(self):
        super(CallbackModule, self).__init__()
        self.start_time = datetime.utcnow().isoformat() + "Z"
        self._display.display("write_l3_summary: plugin loaded OK")

    def v2_playbook_on_stats(self, stats):
        """
        Called when the playbook finishes, after all tasks are complete.
        """

        results = {}
        for host in sorted(stats.processed.keys()):
            s = stats.summarize(host)

            if s.get("failures", 0) > 0 or s.get("unreachable", 0) > 0:
                status = "failed"
            elif s.get("changed", 0) > 0:
                status = "changed"
            else:
                status = "ok"

            results[host] = {
                "ok": s.get("ok", 0),
                "changed": s.get("changed", 0),
                "failed": s.get("failures", 0),
                "unreachable": s.get("unreachable", 0),
                "skipped": s.get("skipped", 0),
                "rescued": s.get("rescued", 0),
                "ignored": s.get("ignored", 0),
                "status": status
            }

        final = {
            "started_at": self.start_time,
            "ended_at": datetime.utcnow().isoformat() + "Z",
            "results": results
        }

        outdir = os.path.join(os.getcwd(), "artifacts", "l3")
        os.makedirs(outdir, exist_ok=True)
        outfile = os.path.join(outdir, "l3_summary.json")

        try:
            with open(outfile, "w") as f:
                json.dump(final, f, indent=2)

            self._display.display(
                f"write_l3_summary: wrote {outfile}"
            )
        except Exception as e:
            self._display.error(f"write_l3_summary: failed to write summary: {e}")
