// Bicep template for mortgage demo app infrastructure
// - Azure SQL Database
// - Storage Account
// - Application Insights
// - Log Analytics Workspace
// - Container App Environment
// - Container Apps for services

param location string = resourceGroup().location

// Use Azure AD authentication only - no SQL authentication
// The service principal already has SQL Server Contributor role assigned at resource group level
param azureAdAdminObjectId string
param azureAdAdminLogin string = 'AzureAD Admin'

var sqlServerName = uniqueString(resourceGroup().id, 'sqlserver')
var sqlDbName = 'mortgageappdb'
var storageAccountName = uniqueString(resourceGroup().id, 'storage')
var appInsightsName = uniqueString(resourceGroup().id, 'appinsights')
var logAnalyticsWorkspaceName = uniqueString(resourceGroup().id, 'logs')
var containerAppEnvName = uniqueString(resourceGroup().id, 'appenv')

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    // No SQL authentication - using only Azure AD authentication
    version: '12.0'
  }
}

// Set up Azure AD Administrator for SQL Server
resource sqlServerADAdmin 'Microsoft.Sql/servers/administrators@2022-05-01-preview' = {
  name: 'ActiveDirectory'
  parent: sqlServer
  properties: {
    administratorType: 'ActiveDirectory'
    login: azureAdAdminLogin
    sid: azureAdAdminObjectId
    tenantId: subscription().tenantId
  }
}

// Enable Azure AD-only authentication to enforce security best practices
resource sqlServerAADOnly 'Microsoft.Sql/servers/azureADOnlyAuthentications@2022-05-01-preview' = {
  name: 'Default'
  parent: sqlServer
  properties: {
    azureADOnlyAuthentication: true
  }
  dependsOn: [
    sqlServerADAdmin
  ]
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

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource containerEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

param loanProcessingImage string
param customerServiceImage string
param webUiImage string
@secure()
param registryUsername string
@secure()
param registryPassword string
param registryServer string

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
      registries: [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [        {
          name: 'loan-processing-service'
          image: loanProcessingImage
          resources: {
            cpu: 1
            memory: '2Gi'
          }
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
      registries: [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [        {
          name: 'customer-service'
          image: customerServiceImage
          resources: {
            cpu: 1
            memory: '2Gi'
          }
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
      registries: [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [        {
          name: 'web-ui'
          image: webUiImage
          resources: {
            cpu: 1
            memory: '2Gi'
          }
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
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.id
