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

// Container registry configuration
// Using key-based authentication for container registry since managed identity isn't working
// We've removed the managed identity parameters since we're now exclusively using key-based auth

var sqlServerName = uniqueString(resourceGroup().id, 'sqlserver')
var sqlDbName = 'mortgageappdb'
var storageAccountName = uniqueString(resourceGroup().id, 'storage')
var appInsightsName = uniqueString(resourceGroup().id, 'appinsights')
var logAnalyticsWorkspaceName = uniqueString(resourceGroup().id, 'logs')
// Use a consistent name for the container app environment to avoid conflicts
var containerAppEnvName = 'mortgageapp-env'
var managedIdentityName = 'mortgageapp-identity'

// Create managed identity for container apps
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

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

// Define the default blob service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storage
}

// Create the container for mortgage app data
resource mortgageDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'mortgage-data'
  parent: blobService
  properties: {
    publicAccess: 'None'
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
    // Add WorkloadProfiles for improved performance
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

param loanProcessingImage string
param customerServiceImage string
param webUiImage string
param registryServer string
param registryUsername string = 'ContainerAppsPlatformAdmin'
@secure()
param registryPassword string = ''

// Note: Since we're now using key-based authentication for ACR, we don't need to extract the registry name or create an acrResourceId anymore

// Loan Processing Service
resource loanProcessingApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'loan-processing-service'
  location: location  // Dependencies on managedIdentity and containerEnv are automatically inferred
  identity: {
    type: 'SystemAssigned'  // Only using system-assigned identity for the app itself, not for ACR
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {      
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: false
        // Add transport settings for better reliability
        transport: 'auto'
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
      activeRevisionsMode: 'Single'      // Set increased timeout for startup operations
      dapr: {
        enabled: false
      }
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
            }, {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'  // Ensure app listens on the right port
            }, {
              name: 'CONTAINER_APP_ENV'
              value: 'true'  // Help the app know it's running in a container app
            }, {
              name: 'CONTAINER_APP_STARTUP'
              value: 'true'  // Indicate to app it's in startup phase
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 5
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 5
              successThreshold: 1
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
    type: 'SystemAssigned'  // Only using system-assigned identity for the app itself, not for ACR
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        allowInsecure: false
        transport: 'auto'
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
      dapr: {
        enabled: false
      }
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
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 5
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/actuator/health/readiness'
                port: 8080
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 5
              successThreshold: 1
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
    type: 'SystemAssigned'  // Only using system-assigned identity for the app itself, not for ACR
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
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
      dapr: {
        enabled: false
      }
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
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 5
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: 80
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 5
              successThreshold: 1
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

// Note: We've removed role assignments for AcrPull because we're now using key-based authentication 
// (registry username/password) for container apps to pull images from ACR.
// This is more reliable and works across subscriptions and resource groups.

// Removed parameter and role assignments:
// - param assignAcrRoles
// - loanProcessingAcrPullRole resource
// - customerServiceAcrPullRole resource
// - webUiAcrPullRole resource

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
