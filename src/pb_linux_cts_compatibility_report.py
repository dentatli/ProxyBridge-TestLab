"""Strict direct Windows CTS / Linux push-receiver compatibility evidence.

This does not establish a ProxyBridge route, timing equivalence or capacity.
"""
import argparse
import csv
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import uuid

METHOD = "linux-cts-direct-compatibility-v1"
TRANSLATED_METHOD = "linux-cts-data-compatibility-v2"
ENGINE = "0548089e59c872306ce2c98e7163e2a717119756010cf64d3cb3da2854f632cf"
PAYLOAD = "164092c58aab2e780e51550c1921baa0aa0c1c1f728e7ddf33a449fa992edef1"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def off(root, phase):
    state = read(root / ("interception-" + phase + ".json"))
    loaded = read(root / ("loaded-drivers-" + phase + ".json"))
    processes = read(root / ("product-processes-" + phase + ".json"))
    require(state["current_driver_preparation_allowed"] and state["wfp_detachment_observed"]
            and state["wfp"]["service_state"] == "Stopped", "WFP_OFF_UNCONFIRMED")
    wd = state["windivert"]
    require(wd["configured"] and wd["files_verified"] and wd["capture_complete"]
            and wd["status"] == "NO_HANDLES_OBSERVED" and wd["observed_handle_count"] == 0,
            "WINDIVERT_OFF_UNCONFIRMED")
    require(loaded["query_complete"] and loaded["known_interception_driver_names_absent"]
            and processes == [], "PRODUCT_OFF_UNCONFIRMED")
    return loaded["other_driver_names_sha256"]


def guid(value):
    require(isinstance(value, str), "GUID_TYPE_INVALID")
    return str(uuid.UUID(value))


def expected_args(host, csv_path):
    return ["-target:" + host, "-port:54122", "-protocol:tcp", "-pattern:push",
            "-transfer:524288", "-ratelimit:65536", "-buffer:65536", "-verify:data",
            "-connections:4", "-iterations:1", "-throttleconnections:32", "-conn:ConnectEx",
            "-shutdown:rude", "-consoleverbosity:1", "-statusupdate:250",
            "-connectionfilename:" + csv_path]


def endpoint(value):
    address, port = value.rsplit(":", 1)
    address = ipaddress.IPv4Address(address)
    port = int(port)
    require(not address.is_unspecified and not address.is_loopback and not address.is_multicast
            and str(address) != "255.255.255.255" and 1 <= port <= 65535,
            "NATIVE_LOCAL_ENDPOINT_INVALID")
    return [str(address), port]


def evaluate(root, endpoint_policy="strict-reciprocal"):
    errors = []
    result = dict(schema_version=1, method=METHOD, status="INCOMPLETE", diagnostic_only=True,
                  native_client_compatibility_verified=False, product_route_verified=False,
                  performance_comparable=False, maximum_capacity_verified=False,
                  errors=errors, verified_connections=0)
    if endpoint_policy == "guid-correlated":
        result.update(method=TRANSLATED_METHOD, endpoint_policy=endpoint_policy)
    try:
        require(endpoint_policy in ("strict-reciprocal", "guid-correlated"), "ENDPOINT_POLICY_INVALID")
        manifest = read(root / "run-manifest.json")
        plan = read(root / "sealed-plan.json")
        require(manifest["status"] == "COMPLETED" and not manifest["errors"]
                and manifest["method"] == plan["method"]
                and plan["method"] in ((METHOD,) if endpoint_policy == "strict-reciprocal" else (METHOD, TRANSLATED_METHOD)),
                "RUN_OR_CLEANUP_INCOMPLETE")
        if plan["method"] == TRANSLATED_METHOD:
            require(plan["endpoint_policy"] == endpoint_policy, "PLAN_ENDPOINT_POLICY_DIFFERS")
        require(sha(root / "sealed-plan.json") == manifest["plan_sha256"], "PLAN_COPY_DIFFERS")
        require(plan["engine_sha256"] == ENGINE and plan["requested_connections"] == 4
                and plan["transfer_bytes"] == 524288 and plan["port"] == 54122,
                "METHOD_BINDING_DIFFERS")
        require(off(root, "before") == off(root, "after"), "OTHER_DRIVER_INVENTORY_DIFFERS")
        launch = read(root / "client-launch.json")
        client = read(root / "client-process.json")
        require(launch["engine_sha256"] == ENGINE and launch["arguments"] ==
                expected_args(plan["host"], launch["csv_path"]), "NATIVE_ARGUMENTS_DIFFERS")
        require(client["exit_code"] == 0 and not client["timed_out"]
                and client["output_capture_complete"] and not client["forced_stop"]
                and client["actual_path_probe_status"] == "PATH_OBTAINED"
                and client["actual_path"].casefold() == launch["executable"].casefold()
                and client["actual_executable_sha256"] == ENGINE,
                "NATIVE_COMPLETION_OR_IDENTITY_UNCONFIRMED")
        require(re.search(r"Level of verification:\s*Connections & Data", client["stdout"]),
                "NATIVE_DATA_VERIFICATION_UNCONFIRMED")
        payload = (root / "client.csv").read_bytes()
        rows = list(csv.DictReader(payload.decode("utf-16" if payload.startswith(b"\xff\xfe")
                                                   else "utf-8-sig").splitlines()))
        require(len(rows) == 4 and all(r["Result"] == "Succeeded" for r in rows),
                "NATIVE_CONNECTIONS_NOT_ALL_SUCCESSFUL")
        native = {guid(r["ConnectionId"]): r for r in rows}
        require(len(native) == 4, "NATIVE_GUID_NOT_UNIQUE")
        remote = root / "receiver"
        collection = read(remote / "remote-collection.json")
        receipt = read(remote / "collection-receipt.json")
        require(collection["status"] == "RECEIVER_EVIDENCE_COLLECTED"
                and collection["sha256"] == sha(remote / "receiver.jsonl")
                and collection["bytes"] == (remote / "receiver.jsonl").stat().st_size
                and receipt["receiver_sha256"] == plan["receiver_sha256"]
                and receipt["control_sha256"] == plan["control_sha256"]
                and receipt["run_id"] == manifest["receiver_run_id"]
                and receipt["ssh_exit_code"] == 0, "RECEIVER_COLLECTION_BINDING_DIFFERS")
        if endpoint_policy == "guid-correlated":
            require(receipt["result"] == collection, "COLLECTION_RECEIPT_CONTENT_DIFFERS")
        exit_record = collection["exit_receipt"]
        require(exit_record["method"] == "cts-2.0.3.9-push-receiver-v1"
                and exit_record["receiver_sha256"] == plan["receiver_sha256"]
                and exit_record["run_id"] == manifest["receiver_run_id"]
                and exit_record["service_result"] == "success"
                and exit_record["exit_code"] == "exited" and exit_record["exit_status"] == "0",
                "REMOTE_EXIT_NOT_CLEAN")
        events = [json.loads(s) for s in (remote / "receiver.jsonl").read_text(encoding="utf-8").splitlines() if s]
        require(events and all(r["schema_version"] == 1 and r["method"] == "cts-2.0.3.9-push-receiver-v1"
                and r["run_id"] == manifest["receiver_run_id"] for r in events)
                and [r["sequence"] for r in events] == list(range(1, len(events) + 1))
                and len({r["process_id"] for r in events}) == 1
                and all(a["monotonic_ns"] <= b["monotonic_ns"] for a, b in zip(events, events[1:])),
                "RECEIVER_JOURNAL_SEQUENCE_OR_SCOPE_DIFFERS")
        listens = [r for r in events if r["event"] == "LISTENING"]
        stops = [r for r in events if r["event"] == "STOPPED"]
        require(len(listens) == len(stops) == 1 and events[0] == listens[0] and events[-1] == stops[0],
                "RECEIVER_LIFECYCLE_INCOMPLETE")
        listener, stop = listens[0], stops[0]
        require(listener["receiver_sha256"] == plan["receiver_sha256"]
                and listener["cts_client_sha256"] == ENGINE and listener["bind_ipv4"] == plan["host"]
                and listener["port"] == 54122 and listener["transfer_bytes"] == 524288
                and listener["allowed_sources"] == [plan["allowed_source"]]
                and listener["max_connections"] == 4 and listener["max_total_connections"] == 4
                and listener["max_duration_seconds"] == 120, "RECEIVER_LISTENER_BINDING_DIFFERS")
        require(stop["status"] == "CAPTURE_COMPLETE" and stop["accepted"] == stop["completed"] == 4
                and all(stop[k] == 0 for k in ("failed", "rejected", "forced_flow_count",
                        "active_connections", "remaining_handlers", "unexpected_errors")),
                "RECEIVER_TRANSFER_OR_CLEANUP_INCOMPLETE")
        require(not any(r["event"] in ("TRANSFER_FAILED", "REJECTED", "FIXTURE_ERROR") for r in events),
                "RECEIVER_ERRORS_PRESENT")
        verified = [r for r in events if r["event"] == "TRANSFER_VERIFIED"]
        accepted = [r for r in events if r["event"] == "ACCEPTED"]
        ended = [r for r in events if r["event"] == "FLOW_ENDED"]
        require(len(verified) == len(accepted) == len(ended) == 4, "RECEIVER_FLOW_EVENTS_INCOMPLETE")
        receiver = {guid(r["connection_id"]): r for r in verified}
        require(len(receiver) == 4 and set(receiver) == set(native)
                and {guid(r["connection_id"]) for r in accepted} == set(native)
                and {guid(r["connection_id"]) for r in ended} == set(native), "RECIPROCAL_GUIDS_DIFFERS")
        mappings = []
        for key, row in native.items():
            peer = receiver[key]
            require(int(row["SendBytes"]) == 524288 and int(row["RecvBytes"]) == 0
                    and peer["bytes_received"] == 524288 and peer["payload_sha256"] == PAYLOAD
                    and peer["completion_sent"] and peer["close_status"] in ("EOF", "RESET_AFTER_COMPLETION"),
                    "VERIFIED_PAYLOAD_OR_COMPLETION_DIFFERS")
            if endpoint_policy == "strict-reciprocal":
                require(row["RemoteAddress"] == plan["host"] + ":54122"
                        and peer["local"] == [plan["host"], 54122]
                        and peer["peer"][0] == plan["allowed_source"]
                        and row["LocalAddress"] == "%s:%d" % tuple(peer["peer"]),
                        "DIRECT_RECIPROCAL_ENDPOINTS_DIFFERS")
            else:
                require(row["RemoteAddress"] == plan["host"] + ":54122"
                        and peer["local"] == [plan["host"], 54122]
                        and peer["peer"][0] == plan["allowed_source"], "CONTROLLED_DESTINATION_OR_SOURCE_DIFFERS")
                native_local = endpoint(row["LocalAddress"])
                observed_peer = endpoint("%s:%d" % tuple(peer["peer"]))
                first = next(r for r in accepted if guid(r["connection_id"]) == key)
                require(first["local"] == peer["local"] and first["peer"] == observed_peer
                        and first["requested_bytes"] == 524288, "ACCEPTED_FLOW_IDENTITY_DIFFERS")
                final = next(r for r in ended if guid(r["connection_id"]) == key)
                require(first["sequence"] < peer["sequence"] < final["sequence"], "FLOW_EVENT_ORDER_DIFFERS")
                mappings.append(dict(connection_id=key, native_local=native_local,
                                     receiver_peer=observed_peer, receiver_local=peer["local"],
                                     endpoints_equal=native_local == observed_peer))
        if endpoint_policy == "guid-correlated":
            require(len({tuple(r["native_local"]) for r in mappings}) == 4
                    and len({tuple(r["receiver_peer"]) for r in mappings}) == 4,
                    "ENDPOINT_NOT_UNIQUE_WITHIN_RUN")
        result.update(status="NATIVE_CTS_LINUX_COMPATIBILITY_VERIFIED",
                      native_client_compatibility_verified=True, verified_connections=4,
                      verified_bytes=4 * 524288, receiver_sha256=plan["receiver_sha256"])
        if endpoint_policy == "guid-correlated":
            reciprocal = all(r["endpoints_equal"] for r in mappings)
            result.update(method=TRANSLATED_METHOD, source_method=plan["method"],
                          endpoint_policy=endpoint_policy, direct_endpoint_reciprocity_verified=reciprocal,
                          address_change_observed=not reciprocal, translation_mechanism_verified=False,
                          endpoint_correlations=mappings, warnings=[] if reciprocal else [
                              "Endpoint addresses/ports differ across machines; GUID/data compatibility verified, network translation mechanism not observed."])
            if not reciprocal:
                result["status"] = "NATIVE_CTS_LINUX_COMPATIBILITY_VERIFIED_TOPOLOGY_UNCONFIRMED"
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        errors.append(type(exc).__name__ + ": " + str(exc))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--endpoint-policy", choices=("strict-reciprocal", "guid-correlated"), default="strict-reciprocal")
    parser.add_argument("--output-directory", type=Path)
    args = parser.parse_args()
    result = evaluate(args.evidence, args.endpoint_policy)
    output = args.output_directory or args.evidence
    if args.output_directory:
        output.mkdir(parents=False, exist_ok=False)
    (output / "compatibility.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    text = ("# Windows CTS → Linux: совместимость\n\n" + result["status"] + "\n\n"
            + ("Подтверждены 4 соединения и 2 MiB проверенных данных.\n\n" if result["native_client_compatibility_verified"] else "Совместимость не подтверждена.\n\n")
            + "Push/data-only. Маршрут ProxyBridge, штатное закрытие TCP, скорость и ёмкость не проверены.\n")
    if result.get("address_change_observed"):
        text += "\nАдреса/порты на двух машинах различаются. Соединения сопоставлены по уникальным GUID и проверенным данным; механизм преобразования адресов не наблюдался.\n"
        text += "\n| GUID | Windows local | Linux peer |\n| --- | --- | --- |\n"
        for r in result["endpoint_correlations"]:
            text += "| %s | %s:%d | %s:%d |\n" % (r["connection_id"], *r["native_local"], *r["receiver_peer"])
    if result["errors"]:
        text += "\nОшибки:\n" + "\n".join("- " + s for s in result["errors"]) + "\n"
    (output / "summary.md").write_text(text, encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["native_client_compatibility_verified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
