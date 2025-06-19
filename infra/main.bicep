// Bicep template for mortgage demo app infrastructure
// - Azure SQL Database
// - Azure Blob Storage
// - Azure Container Apps Environment
// - Azure Container Apps for each service
// - Application Insights
// - Load Testing resource

param location string = resourceGroup().location
param sqlAdminUsername string = 'sqladminuser'
@secure()
param sqlAdminPassword string

var sqlServerName = uniqueString(resourceGroup().id, 'sqlserver')
var sqlDbName = 'mortgageappdb'
var storageAccountName = toLower(uniqueString(resourceGroup().id, 'mortgagestorage'))
var appInsightsName = 'mortgageapp-ai'
var containerEnvName = 'mortgageapp-env'

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  name: sqlDbName
  parent: sqlServer
  location: location
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    sampleName: 'AdventureWorksLT'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource containerEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: appInsights.properties.InstrumentationKey
        sharedKey: ''
      }
    }
  }
}

param loanProcessingImage string
param customerServiceImage string
param webUiImage string

// Loan Processing Service
resource loanProcessingApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'loan-processing-service'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
      secrets: []
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'loan-processing-service'
          image: loanProcessingImage
          env: [
            {
              name: 'SQL_SERVER_NAME'
              value: sqlServer.name
            }, {
              name: 'SQL_DATABASE_NAME'
              value: sqlDbName
            }, {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storage.name
            }, {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 80
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/ready'
                port: 80
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

// Customer Service
resource customerServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'customer-service'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
      }
      secrets: []
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'customer-service'
          image: customerServiceImage
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/actuator/health/liveness'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/actuator/health/readiness'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

// Web UI
resource webUiApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'web-ui'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
      secrets: []
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'web-ui'
          image: webUiImage
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 10
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}

// Azure Load Testing resource
resource loadTest 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: 'mortgage-loadtest'
  location: location
}

output sqlServerName string = sqlServer.name
output sqlDbName string = sqlDb.name
output storageAccountName string = storage.name
output appInsightsName string = appInsights.name
output containerEnvName string = containerEnv.name
output loadTestName string = loadTest.name
output loanProcessingFqdn string = loanProcessingApp.properties.configuration.ingress.fqdn
output customerServiceFqdn string = customerServiceApp.properties.configuration.ingress.fqdn
