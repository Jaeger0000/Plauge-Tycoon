from constants import FURNITURE_BASE_TIMES, MACHINE_SPEEDS
from models import AssignmentRequest, AssignmentResponse, FurnitureAssignment


def solve_assignment(req: AssignmentRequest) -> AssignmentResponse:
    if not req.furniture_queue:
        return AssignmentResponse(optimal_throughput=0, optimal_assignments=[])

    stages = ["cutting", "assembly", "packaging"]
    machines_per_stage: dict[str, list[str]] = {stage: [] for stage in stages}

    for slot_key, machine_name in req.machines.items():
        if machine_name is None:
            continue
        for stage in stages:
            if stage in slot_key:
                machines_per_stage[stage].append(machine_name)
                break

    best_machine: dict[str, str] = {}
    for stage in stages:
        available = machines_per_stage[stage]
        best_machine[stage] = (
            min(available, key=lambda m: MACHINE_SPEEDS.get(m, 1.0)) if available else "Basic"
        )

    assignments: list[FurnitureAssignment] = []
    total_time_used = 0.0

    for item in req.furniture_queue:
        base = FURNITURE_BASE_TIMES.get(item, {"cutting": 3.0, "assembly": 4.0, "packaging": 2.0})
        total_time = sum(
            base[stage] * MACHINE_SPEEDS.get(best_machine[stage], 1.0) for stage in stages
        )

        if total_time_used + total_time > req.time_remaining:
            break

        total_time_used += total_time
        assignments.append(
            FurnitureAssignment(
                furniture=item,
                cutting_machine=best_machine["cutting"],
                assembly_machine=best_machine["assembly"],
                packaging_machine=best_machine["packaging"],
                total_time=round(total_time, 2),
            )
        )

    return AssignmentResponse(optimal_throughput=len(assignments), optimal_assignments=assignments)
