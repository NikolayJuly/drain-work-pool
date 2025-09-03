# ``WorkPoolDraining``

This package aims to help with execution of a large number of tasks while limiting the number of simultaneously executed tasks.

## Overview

The package provides a few work pools, depending on whether input tasks are known beforehand.  
All work pools in the package are `AsyncSequence`, which work on a push approach. This means that work will be executed even if no one iterates over it.

## Samples

**Map an existing AsyncSequence, limiting the maximum number of concurrent operations**


```
asyncSequence.process(limitingMaxConcurrentOperationCountTo: 5) {
    /* some heavy task */
}
```

**Create a drainer manually**

```
let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 5)
for i in 0..<1024 {
    pool.add { /* some heavy task */ }
}
pool.closeIntake()

for try await i in pool {
    // process result
}
```

## Extensions

There are **process** and **map** options. `map` will keep the order closure of calls, which sometimes might be needed.

**AsyncSequence extension**

``_Concurrency/AsyncSequence`` extension methods:

- ``_Concurrency/AsyncSequence/map(limitingMaxConcurrentOperationCountTo:process:)-4voyy``
- ``_Concurrency/AsyncSequence/map(limitingMaxConcurrentOperationCountTo:process:)-39por``
- ``_Concurrency/AsyncSequence/process(limitingMaxConcurrentOperationCountTo:process:)-6sff``
- ``_Concurrency/AsyncSequence/process(limitingMaxConcurrentOperationCountTo:process:)-95vq2``
- ``_Concurrency/AsyncSequence/process(limitingMaxConcurrentOperationCountTo:process:)-6m7sn``


**Collection extension**

``Swift/Collection`` extension methods:

- ``Swift/Collection/map(limitingMaxConcurrentOperationCountTo:process:)``
- ``Swift/Collection/process(limitingMaxConcurrentOperationCountTo:process:)-9ca0h``
- ``Swift/Collection/process(limitingMaxConcurrentOperationCountTo:process:)-int2``
- ``Swift/Collection/process(limitingMaxConcurrentOperationCountTo:process:)-6360o``


## How to choose correct work pool?

The package contains 2 types of pools: static and dynamic. A dynamic pool allows you to add work tasks while it is executing.  
A static pool, on the other hand, executes the same task on a predefined collection of elements.

On top of that, choose the basis you want: DispatchQueue or Structured Concurrency.

Decision tree:
- Static + DispatchQueue: ``StaticSyncWorkPoolDrainer``
- Static + Structured Concurrency: ``StaticAsyncWorkPoolDrainer``
- Dynamic + Structured Concurrency: ``DynamicAsyncWorkPoolDrainer``

## Why?

Why do we need this package, if we have `TaskGroup`?

`TaskGroup` does not allow limiting the number of simultaneous executions, which is important in some cases:

- Internet bandwidth is limited, so there’s no reason to trigger an unlimited number of connections
- Storage bandwidth is limited, so there’s no reason to start thousands of read/write operations at the same time
- CPU usage needs to be limited because you need to use your Mac while it executes long-running tasks in the background
- Defining QoS is not always enough, as you might want to have more control over the number of simultaneous executions and not depend on QoS heuristics

## Topics

### Work Pool Drainers

- ``DynamicAsyncWorkPoolDrainer``
- ``StaticAsyncWorkPoolDrainer``
- ``StaticSyncWorkPoolDrainer``

