// Everything the support agent runs on, in one resource group. What isn't here yet is in the README, under Deploying.

param location string
param tags object

@description('Five characters that make the names unique, e.g. k3x7q.')
@minLength(5)
@maxLength(5)
param token string

param fabricSqlEndpoint string
param returnsApi string
param supportDeskApi string

@description('The chat model. gpt-5-mini answers the pilot well, for a fraction of the cost of gpt-5.')
param modelName string = 'gpt-5-mini'
param modelVersion string = '2025-08-07'

@description('Thousands of tokens per minute.')
param modelCapacity int = 10

var foundryName = 'ai-contoso-${token}'
var projectEndpoint = 'https://${foundryName}.services.ai.azure.com/api/projects/${project.name}'
var acrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var foundryAgentConsumer = 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6'

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${token}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${token}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryName
    disableLocalAuth: true // Microsoft Entra ID only: there are no keys to leak
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: 'proj-support'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    displayName: 'Customer support'
    description: 'The returns assistant pilot.'
  }
}

resource model 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: modelName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
  dependsOn: [project] // one change to the Foundry resource at a time
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'cr${token}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

// The app's identity: pulls its image, calls the agent, reads the lakehouse and opens returns. Nothing else.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-web-${token}'
  location: location
  tags: tags
}

resource pullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, acrPull)
  scope: registry
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPull)
  }
}

// Foundry Agent Consumer: the chat can talk to the project's agents through their endpoints, and nothing else.
// Publishing and promoting versions is for people, from src/agent.py.
resource projectRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, identity.id, foundryAgentConsumer)
  scope: project
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', foundryAgentConsumer)
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${token}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource web 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-web-${token}'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: identity.id
        }
      ]
      secrets: [
        {
          name: 'appinsights-connection-string'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'web'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest' // until azd deploy builds ours
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'FOUNDRY_PROJECT_ENDPOINT', value: projectEndpoint }
            { name: 'FOUNDRY_MODEL_NAME', value: model.name }
            { name: 'FABRIC_SQL_ENDPOINT', value: fabricSqlEndpoint }
            { name: 'RETURNS_API', value: returnsApi }
            { name: 'SUPPORT_DESK_API', value: supportDeskApi }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'appinsights-connection-string' }
            { name: 'AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING', value: 'true' }
            { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
          ]
        }
      ]
      scale: {
        minReplicas: 1 // no cold starts while 50 people are using it
        maxReplicas: 3
      }
    }
  }
  dependsOn: [pullRole] // or the first pull fails
}

output registryEndpoint string = registry.properties.loginServer
output projectEndpoint string = projectEndpoint
output modelName string = model.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output webUrl string = 'https://${web.properties.configuration.ingress.fqdn}'
