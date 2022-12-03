# WorkPoolDraning
![swift](https://img.shields.io/badge/Swift-5.7-orange.svg)

This package contains 2 classes, which aim to help orgnize heavy operations and limit simultnious load on computer resources

## AsyncOperationsPool

Helps organize async tasks

Usage: 
```
let pool = AsyncOperationsPool<Int>(maxConcurrentOperationCount: 5)
for i in 0..<1024 {
    pool.add { /* some heavy async task */ }
}
///
for try await i in pool {
  // process result
}
```


## StackDrainer

Helps orgnize sync tasks 

Usage: 
```
let drainer = StackDrainer(queuesPoolSize: 5, stack: files)
let processedFiles = drainer.drain { file in /* heavy operation on input file */ }
for processedFile in processedFiles {
    // work with processed files
}
```
