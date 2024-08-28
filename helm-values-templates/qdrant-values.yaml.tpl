fullnameOverride: "qdrant"

resources:
  limits:
    cpu: 1
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi

persistence:
  size: 50Gi

# modification example for configuration to overwrite defaults
config:
  cluster:
    enabled: false