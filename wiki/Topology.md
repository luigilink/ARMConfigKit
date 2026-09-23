# Topology

The sample topology deploys a small farm, but the design is **not limited to a fixed
number of machines** — the VM list is data-driven (`vms_informations` in
`terraform/variables.tf`) and SPSConfigKit scales to any number of nodes, so you can
add or remove servers to match your scenario.

## Sample farm

The default sample provisions:

| Role | VM   | Purpose                                     |
| ---- | ---- | ------------------------------------------- |
| PDC  | PDC1 | Active Directory domain controller          |
| PULL | PULL | DSC pull server / software share            |
| SQL  | SQL1 | SQL Server                                  |
| APP  | APP1 | SharePoint application server               |
| SCH  | SCH1 | SharePoint search server                    |
| WFE  | WFE1 | SharePoint web front end                    |
| OOS  | OOS1 | Office Online Server                        |
| SWM  | SWM1 | Workflow Manager                            |
| ARR  | ARR  | Application Request Routing (reverse proxy) |

## Scaling the farm

The VM list is defined by the `vms_informations` variable in
`terraform/variables.tf`. Add or remove entries to match your scenario — for example a
single-server lab, or a multi-WFE / multi-APP production-like topology. ARMConfigKit
provisions exactly the VMs you declare, and [SPSConfigKit](https://github.com/luigilink/SPSConfigKit)
configures the SharePoint roles on top of them, so the two kits scale together.
