![swift](https://img.shields.io/badge/Swift-5.9-orange.svg)

# WorkPoolDraning

This package aim to help with execution of big amount of tasks, but limit number of simultaneously executed tasks.

## Installation

```
dependencies: [
    .package(url: "https://github.com/NikolayJuly/drain-work-pool.git", from: "3.0.0"),
]
```

Include "WorkPoolDraning" as a dependency for your target:

```
.target(name: "<target>", dependencies: [
    .product(name: "WorkPoolDraning", package: "drain-work-pool"),
]),
```

## Overview

Package provides few work pools, depending on knowledge of input tasks beforehand. 
All work pools in package are `AsyncSequence`, which works on push approach. It means that work will be executed even if no one iterate over it.


## How to choose correct work pool?

Package contains 2 type of pools: static and dynamic. Dynamic pool allow you to add work tasks while it is executing. 
Static pool, on the other hand, execute same task on predefined collection of elements.

On top of that, choose which basis you want: DispatchQueue or Structured Concurrency.

Decision tree:
- Static + DispatchQueue: ``StaticSyncWorkPoolDrainer``
- Static + Structured Concurrency: ``StaticAsyncWorkPoolDrainer``
- Dynamic + Structured Concurrency: ``DynamicAsyncWorkPoolDrainer``

## Process existed collection

Also you can use `process` method on `Collection` or `AsyncSequence`. 
Keep in mind that closure might be called in random order, depending on an execution speed of each process call.
```
try await array.process(limitingMaxConcurrentOperationCountTo: 5, { ... })
```

## Why?

Why do we need this package, if we have TaskGroup?

`TaskGroup` do not allow to limit number of simultaneous executions, which is important in some cases:

- Internet bandwidth is limited, no reason to trigger unlimited amount of connections
- Storage bandwidth is limited, no reason to start thousands of read/write operations at the same time
- Needs to limit CPU usage, because you need to use mac, while it executes long running tasks in background
- Define QoS not always enough, as you might want to have more control over number of simultaneous executions and do not depend on QoS evristics


## Documentation

Swift DocC documentation is available [here](https://nikolayjuly.github.io/drain-work-pool/documentation/workpooldraning/)
