# WorkPoolDraning
![swift](https://img.shields.io/badge/Swift-5.7-orange.svg)

This package contains 2 classes, which aim to help orgnize heavy operations and limit simultaneous load on computer resources.
You can choose one, which fit your needs:
- [StaticSyncWorkPoolDrainer](Sources/WorkPoolDraning/StaticSyncWorkPoolDrainer.swift) - works with predefined stack of elements and execute same task on all of them. Task block must be sync
- [DynamicAsyncWorkPoolDrainer](Sources/WorkPoolDraning/DynamicAsyncWorkPoolDrainer.swift) - work with dynamicly growing pool of work. Task block can be async

### Why do we need these classes, if we have TaskGroup? ###
`TaskGroup` do not allow to limit number of simultaneous executions, which is important in some cases:
- Internet bandwidth is limited, no reason to trigger unlimited amount of connections
- Storage bandwidth is limited, no reason to start thousands of read/write operations at the same time
- Needs to limit CPU usage, becase you need to use mac, while it executes long running tasks in background
- Define QoS not always enough, as you might want to have more control over number of simultaneous excutions and do not depend on QoS evristics