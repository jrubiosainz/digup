targetScope = 'subscription'

@minLength(1)
@maxLength(20)
@description('The azd environment, e.g. dev. Part of every resource name.')
param environmentName string

@minLength(1)
@description('Region for everything. Foundry Agent Service and gpt-5-mini must both be available there.')
param location string

@description('SQL analytics endpoint of the contoso_sales lakehouse: azd env set FABRIC_SQL_ENDPOINT …')
param fabricSqlEndpoint string = ''

@description('Base URL of the returns API: azd env set RETURNS_API …')
param returnsApi string = ''

@description('Base URL of the support desk API: azd env set SUPPORT_DESK_API …')
param supportDeskApi string = ''

var tags = {
  'azd-env-name': environmentName
  owner: 'customer-care'
  workload: 'support-agent'
}
var token = take(toLower(uniqueString(subscription().id, environmentName, location)), 5)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-contoso-support-${environmentName}'
  location: location
  tags: tags
}

module app 'resources.bicep' = {
  name: 'support-agent'
  scope: rg
  params: {
    location: location
    tags: tags
    token: token
    fabricSqlEndpoint: fabricSqlEndpoint
    returnsApi: returnsApi
    supportDeskApi: supportDeskApi
  }
}

// azd keeps these in .azure/<environment>/.env: azd env get-values prints them.
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = app.outputs.registryEndpoint
output FOUNDRY_PROJECT_ENDPOINT string = app.outputs.projectEndpoint
output FOUNDRY_MODEL_NAME string = app.outputs.modelName
output APPLICATIONINSIGHTS_CONNECTION_STRING string = app.outputs.appInsightsConnectionString
output WEB_URL string = app.outputs.webUrl
