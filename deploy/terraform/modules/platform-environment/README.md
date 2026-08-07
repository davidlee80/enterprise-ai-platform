# Platform environment composition

Internal composition module that reuses all eight capability contracts for
dev, stage, and prod. It contains no provider resources and is not a ninth
infrastructure capability. Leaf modules own validation; environment roots own
independent state and reviewed inputs.

