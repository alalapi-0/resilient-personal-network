"""Publish the saved client-fixture result as one standard Hub snapshot."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ID = "resilient-personal-network"
ADAPTER = "client_fixture"


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--hub-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    args = parser.parse_args(argv)

    hub_root = args.hub_root.resolve(strict=True)
    project_root = args.project_root.absolute()
    if project_root.is_symlink() or not project_root.is_dir():
        return 2
    project_root = project_root.resolve(strict=True)
    sys.path.insert(0, str(hub_root / "src"))

    from hub.connection_sources import SourceResolver
    from hub.metric_collect import validate_metric_source_config
    from hub.metric_export import export_metric_snapshot
    from hub.metric_fixture_report import collect_fixture_report
    from hub.metric_sources import read_structured
    from hub.metrics import utcnow

    observed_at = utcnow()
    resolver = SourceResolver(hub_root, clock=lambda: observed_at)
    registered = Path(resolver.projects[PROJECT_ID]["root_path"]).expanduser()
    if registered.resolve(strict=True) != project_root:
        return 2
    config, _ = read_structured(hub_root, "data/connections/metric_sources.yaml")
    validate_metric_source_config(config, resolver.projects)
    spec = config["projects"][PROJECT_ID]
    if spec["adapter"] != ADAPTER:
        return 2
    management = resolver.refresh(PROJECT_ID)
    if not management["success"]:
        return 2

    def fixture(project, project_id, observed):
        return collect_fixture_report(project, project_id, observed, spec)

    export_metric_snapshot(
        project_root,
        PROJECT_ID,
        {"validation": fixture},
        exporter_id="resilient-personal-network-export",
        exporter_version="1.0",
        management=management,
        clock=lambda: observed_at,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
