# Issue: The attestation policy name does not match the policy that runs

Suggested title: **AS: make the stored attestation policy name the one that runs**

## Problem

Operators hit this when they install an attestation policy and then attest a guest.

```shell
kbs-client ... set-attestation-policy --id default --policy-file my-cpu.rego
```

The upload succeeds and stores `default`. When a guest later attests using policy id `default`, that attestation does not read the uploaded file. It reads the built-in `default_cpu`, `default_gpu`, `default_switch`, and `default_ppcie`. The token still says the policy name is `default`. The uploaded file has no effect.

Omitting the name stores `default_cpu` only. GPU, switch, and PPCIE stay on the built-in policies. The token still says `default` on every entry, so it does not show that only CPU changed.

A custom policy takes effect only when the uploaded names carry a suffix and the request does not:

```shell
kbs-client ... set-attestation-policy --id acme_cpu    --policy-file cpu.rego
kbs-client ... set-attestation-policy --id acme_gpu    --policy-file gpu.rego
kbs-client ... set-attestation-policy --id acme_switch --policy-file switch.rego
kbs-client ... set-attestation-policy --id acme_ppcie  --policy-file ppcie.rego
```

The request selects `acme`. Attestation reads `acme_cpu`, `acme_gpu`, `acme_switch`, and `acme_ppcie`. The token says `acme`.

A configuration written as `bob-cpu` and `bob-gpu` is looked up as `bob-cpu_cpu` and `bob-cpu_gpu`. `bob-gpu` is ignored.

## What has to be decided together

KBS can already ask AS to evaluate several policy ids. This issue does not discuss how KBS chooses those ids, or what selector it shows to a guest. It only looks at the ids AS is given.

Those ids are doing three jobs, so the names collide.

1. **The policy name.** The name used when setting a policy, the name used in the attestation request, and the policy name in the token. Today a file takes effect only as `default_cpu`, while the request and the token say `default`.
2. **How a device result finds a policy.** The key today is the fixed set `cpu`, `gpu`, `switch`, `ppcie`. `cpu` holds TDX and vTPM together, and their coverages differ. `ppcie` is an NVIDIA topology summary, but the four slots look as if every policy set must include all of them.
3. **The submodule name in the token.** Submodules are named `cpu0` and `gpu0`. That word is also the key in (2) and the suffix in (1). A policy name, a device name, and a submodule name are three roles.

The proposals below each take a position on all three.

## Proposal A: one policy file, one name

The name used to set, store, request, and record the policy is one string. CPU, GPU, switch, and PPCIE rules live in that file. There is no second key that opens another file. Submodules stay `cpu0` and `gpu0`.

The four built-in policies become one file.

```rego
package policy

import rego.v1

cpu_hardware := 2 if {
	input.tdx
	input.tdx.td_attributes.debug == false
} else := 97 if {
	input.tdx
}

gpu_hardware := 2 if {
	input.nvidia["x-nvidia-gpu-attestation-report-signature-verified"]
} else := 97 if {
	input.nvidia["x-nvidia-gpu-attestation-report-parsed"]
}

trust_claims["cpu"] := { "hardware": cpu_hardware } if { cpu_hardware }
trust_claims["gpu"] := { "hardware": gpu_hardware } if { gpu_hardware }
```

A missing device must not be placed in the same object as the others, or the whole result disappears. Scores on each submodule stay flat. The nesting exists only inside this policy. Two GPUs are still `gpu0` and `gpu1`.

TDX and vTPM still have to be separated inside the file, so the file grows one section per result shape. Replacing the software-stack rules means editing the hardware rules.

## Proposal B: one policy per submodule

Each policy file produces one submodule, and that submodule's policy id is the id of that file. AS is given those ids directly. There is no group name on the AS side, and no suffix is added.

Each device verification result carries a device name. A policy lists the names it accepts. AS runs a policy only when that list contains the device name. The four slots are not the key.

The submodule name is written by the policy. If two submodules in one token would get the same name, that is a configuration error. AS does not add an index to tell them apart.

Device names follow the shape of the result, not the product generation. TDX and SNP have different fields, so they are two names. Hopper and Blackwell share one set of fields, so they share `nvidia-gpu`. A switch is `nvidia-switch`. PPCIE is not a card, so it is `nvidia-ppcie`. A later generation with a different result shape gets its own name. NVIDIA results do not carry these names today. Verifiers have to add them before a list can select them.

```rego
# policy id: cpu
devices := ["tdx", "snp"]
submod := "cpu"

hardware := 2 if {
	input.tdx
	input.tdx.td_attributes.debug == false
} else := 2 if {
	input.snp
} else := 97 if {
	input.tdx
}

trust_claims := { "hardware": hardware }
```

```rego
# policy id: runtime-rtmr
# This list does not include nvidia-gpu, so the policy does not run on a GPU result.
devices := ["tdx", "vtpm"]
submod := "runtime"

executables := 3 if {
	input.tdx
	input.init_data_claims.runtime == "runtime1"
} else := 33 if {
	input.tdx
}

trust_claims := { "executables": executables }
```

A TDX result matches both lists, so the token has two submodules: `cpu` from policy `cpu`, and `runtime` from policy `runtime-rtmr`. An SNP result matches only `cpu`. A vTPM result matches only `runtime-rtmr`.

If `runtime-rtmr` also set its submodule name to `cpu`, that would be a configuration error on a TDX result. The two scores are not merged, and no index is added.

The four built-in policies stay as separate files on AS. Each gains a device-name list and a submodule name. AS is asked for those policy ids directly. `default` is not a name AS resolves.

## Proposal C: one group name, several subclass policies

KBS keeps one group name and the subclass policy names it stands for. AS only receives the subclass policy names. A CPU result is evaluated with the `cpu` policy KBS passed in, a GPU result with the `gpu` policy, and the same for switch and PPCIE. AS does not append a subclass to a group name.

```text
group name     default
subclass files default_cpu, default_gpu, default_switch, default_ppcie
```

Setting the group `acme` stores `acme_cpu`, `acme_gpu`, `acme_switch`, and `acme_ppcie`. Attesting with `acme` reads those files. The token records the group name `acme`, not the subclass file name. Submodules stay `cpu0` and `gpu0`.

The four slots stay. `cpu` still holds TDX and vTPM together. A group is expected to have a file for each slot, including `ppcie`.

## Comparison

|                                    | A: one file                            | B: one policy per submodule                                                         | C: one group name, subclass files                          |
| ---------------------------------- | -------------------------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Names                              | One string for set, request, and token | The policy id given to AS is the id stored and the id on that submodule | One group name on the KBS side maps to several subclass policy ids. AS sees only those ids. The token shows the group name |
| How a device result finds a policy | Inside the one file, by device         | Match the device name against the policy's list                                     | Group name plus subclass (`cpu`, `gpu`, `switch`, `ppcie`) |
| Submodule name                     | Device class plus an index             | Written by the policy. A repeated name is a configuration error                     | Device class plus an index                                 |
| The four built-in policies         | Folded into one file                   | Kept. Each gains a list and a submodule name. AS is given their ids                 | Kept as the subclass files of the group `default`          |

We propose B. It's more clear and user-friendly. B could also support policy ID group administration, and we can add it later if really needs.

A keeps hardware rules and software-stack rules in the same file and will explode.

C keeps the four subclasses, so TDX and vTPM still share `cpu`, and every group still has a `ppcie` slot.

## Out of scope

- Who chooses which policy ids KBS sends to AS. KBS can already send several. This issue only says what AS does with the ids it receives.
- Merging two policies' scores into one submodule, or adding an index when two submodules would share a name.

## Related

- [#863](https://github.com/confidential-containers/trustee/issues/863) describes the gap between the name used when setting a policy and the name that is read.
- [#964](https://github.com/confidential-containers/trustee/issues/964) is the confusion between the words `default` and `default_cpu`.
