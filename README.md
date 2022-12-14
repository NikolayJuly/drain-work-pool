![swift](https://img.shields.io/badge/Swift-5.7-orange.svg)

# WorkPoolDraning

This package aim to help with execution of big amount of tasks, but limit number of simultaneously executed tasks.

## Overview

Package provides few work pools, depending on knowledge of input tasks beforehand. 
All work pools in package are `AsyncDequence`, which works on push approach. It means that work will be executed even if no one iterate over it.


## How to choose correct work pool?

Package contains 2 type of pools: static and dynamic. Dynamic pool allow you to add work tasks while it is executing. 
Static pool, on the other hand, execute same task on predefined stack of elements.

On top of that, choose which basis you want: DispatchQueue or Structured Concurrency.

Decision tree:
- Static + DispatchQueue: ``StaticSyncWorkPoolDrainer``
- Static + Structured Concurrency: ``StaticAsyncWorkPoolDrainer``
- Dynamic + Structured Concurrency: ``DynamicAsyncWorkPoolDrainer``

## Why?

Why do we need these package, if we have TaskGroup?

`TaskGroup` do not allow to limit number of simultaneous executions, which is important in some cases:

- Internet bandwidth is limited, no reason to trigger unlimited amount of connections
- Storage bandwidth is limited, no reason to start thousands of read/write operations at the same time
- Needs to limit CPU usage, because you need to use mac, while it executes long running tasks in background
- Define QoS not always enough, as you might want to have more control over number of simultaneous excutions and do not depend on QoS evristics


## Documentation

Swift DocC documentation is available [here](https://nikolayjuly.github.io/drain-work-pool/documentation/workpooldraning/)
