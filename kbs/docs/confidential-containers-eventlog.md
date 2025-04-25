# Specification for AAEL and CoCo Event Spec in Confidential Containers

## Introduction

The Attestation Agent Eventlog ([AAEL](https://github.com/confidential-containers/guest-components/issues/495)) and CoCo Event Spec are introduced to address limitations in existing logging frameworks such as [Confidential Computing Eventlog (CCEL)](https://uefi.org/specs/UEFI/2.10/38_Confidential_Computing.html), which primarily focus on capturing events during OS boot-up. The AAEL standard offers a comprehensive format for user-space event logging, which is crucial for a broad range of confidential computing scenarios, ensuring events are coherently bound to hardware dynamic measurement registers. This enables high integrity and verifiability for operations occurring beyond OS startup. The CoCo Event Spec builds upon the AAEL framework, specifying event types pertinent to the unique context of Confidential Containers. Together, these specifications support the development of complex security policies by offering structured and standardized event logging across varied computing environments.

## Architecture

The architecture supporting AAEL and CoCo Event Spec seamlessly integrates with existing confidential computing systems,
providing a robust framework for user-space event logging and verification. The [Attestation Agent (AA)](https://github.com/confidential-containers/guest-components/tree/main/attestation-agent) is integral to this process, recording events within the AAEL framework and securely binding logs to hardware dynamic measurement registers.
It receives log information from application components such as those handling container images via image-rs and managing container lifecycle events with kata-agent in CoCo scenarios.
These callers record events following the spec-defined CoCo Event Type, ensuring consistency and reliability in log data.

The Attestation Server (AS) offers a flexible platform for processing AAEL logs in a generalized manner, ensuring compatibility with various confidential computing environments for diverse event verification.
Furthermore, AS can conduct detailed analysis and enforce policies for CoCo events, utilizing the CoCo Event Spec for precise validation and scrutiny. This capability supports the development and execution of advanced security policies, enhancing the effectiveness and security of containerized workloads.

```                                    
                       ┌───────┐         
                       │ App   │         
                       └───┬───┘         
                           │             
                           │             
                           │             
     Record     ┌──────────▼──────────┐  
    ┌───────────┤                     │  
    │           │  Attestation Agent  │  
┌───▼──┐        │                     │  
│ AAEL │        └───┬─────────────────┘  
│      │            │                    
│      │            │                    
│      │     Extend │                    
└──────┘            │                    
                    │                    
              ┌─────▼───────────────────┐
              │ Runtime Measurements/PCR│
              └─────────────────────────┘
```

In this specification, we provide detailed information on the Attestation Agent Event Log (AAEL) format in confidential
computing scenarios, as well as the specific CoCo Event Entry format for Confidential Containers (CoCo).
Currently, as the kernel does not offer a unified interface for maintaining Eventlogs [1], we have decided to temporarily use the AAEL to accommodate CoCo Event Entries. 
Once the kernel releases a unified Eventlog format, we will update the next version of the specification to ensure that the existing CoCo Event Entries are compatible with the new Kernel Eventlog format. We will also strive to minimize any impact on the user experience for existing users.

## Specifications

This specification is divided into two sections: AAEL and CoCo Event Spec. AAEL is a standard for user-space event logging, while CoCo Event Spec is a specification for event types pertinent to the unique context of Confidential Containers.

### Attestation Agent Event Log (AAEL)

1. Binding of AAEL with Dynamic Measurement Registers

Entries recorded by AAEL are bound to a specific PCR register value. With each new event added, an extend operation is
performed on the designated PCR register. When the platform provides a (v)TPM interface, the PCR register corresponds
to the (v)TPM's PCR register. On a platform that is solely TEE, PCR is mapped to a specific [Confidential Computing event log Measurement Register (CCMR)](https://uefi.org/specs/UEFI/2.10/38_Confidential_Computing.html#virtual-platform-cc-event-log)
according to platform-specific rules. This mapping ensures AAEL has applicability even outside TEE scenarios.

2. AAEL Log Entry Format

AAEL log entries consist of two types: Event Entry and INIT Entry. 

__INIT Entry__ is recorded only once at the beginning of AAEL when AA first initializes, capturing the current value of a specific PCR, formatted as

```
INIT/<hash-algorithm> <hex-digest>
```
Where,
- `<hash-algorithm>`: may be `sha256`, `sha384`, or `sha512`.
- `<hex-digest>` is the base16-encoded PCR register value. The length MUST be aligned with the `<hash-algorithm>`. Padding with zeros or truncation MUST be applied if necessary to align with the digest length.

__Event Entry__ records specific events in the format
```
<Domain> <Operation> <Content>
```

Where,
- `Domain`: the event domain, RECOMMENDED to be a URI.
- `Operation`: the specific operation within the domain.
- `Content`: detailed context of the operation.

The three fields are separated by spaces. Each field MUST not contain spaces or delimiters and MUST be composed of [printable character](https://www.ascii-code.com/characters/printable-characters).
The three fields are defined by the specific application layer.

### Confidential Containers Event Spec

Confidentail Containers Event (CoCo Event) Spec is a specification for event types pertinent to the unique context of Confidential Containers.
It is designed to be a flexible and extensible format that can be used to represent a variety of events in a Confidential Container environment.
The CoCo Event Spec is based on the AAEL specification.

CoCo events MUST have a `domain` set as `github.com/confidential-containers`.

Content fields MUST be in JSON format, without spaces or delimiters.

Concrete supported `Operation`s and `Content`s are defined in the following table:
| Operation | Content | Description | Content Example |
| --- | --- | --- |
| `PullImage` | `{"image":"<image-reference>","digest":"<digest>:<hex>"}` | An image pulling event with image reference and manifest digest | `{"image":"alpine","digest":"sha256:0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0"}`

## References

[1] https://lore.kernel.org/linux-coco/42c5eba9-381b-4639-9131-f645b375d235@linux.intel.com/T/#m086550ee8ca4d0127657ca8a467bf7cf170bfb74