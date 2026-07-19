// Wear The Mood — Azure Container Apps IaC (blueprint §11.13, §3.4 spend guards).
// Consumption ACA only. Storage QUEUE only (Standard_LRS). No ACR/VM/DB/Service Bus/
// Front Door. Managed identity for queue access; GHCR pull + app secrets via ACA
// secret refs. Scale/resource settings are LOCKED — do not raise without approval.
//
// Validate:  az bicep build --file infra/azure/main.bicep
// Deploy:    az deployment group create -g wtm-prod -f infra/azure/main.bicep -p @params.<env>.json

targetScope = 'resourceGroup'

@description('''
Locked deploy region. Blueprint §13.2 specifies `eastus`, but the Azure for Students
subscription enforces the Microsoft-managed policy "Allowed resource deployment
regions" = [koreacentral, austriaeast, uaenorth, malaysiawest, centralindia] — no US
region is permitted, and austriaeast has no Container Apps support. `koreacentral` is
the approved substitute (Phase 4, founder decision): full ACA support and the lowest
RTT to Supabase us-east-1 (~180-200 ms) of the four viable regions. Revisit if the
subscription's region policy is ever widened via Azure support.
''')
param location string = 'koreacentral'
param namePrefix string = 'wtm-prod'

@description('Globally-unique lower-case Standard_LRS storage account, e.g. wtmprod<suffix>. Record in MIGRATION_STATE.md.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Log Analytics retention — 30-day maximum (§3.4).')
@maxValue(30)
param logRetentionDays int = 30

@description('Immutable commit-SHA / digest image refs in GHCR.')
param apiImage string
param rembgImage string
param orchestratorImage string

param ghcrUsername string
@secure()
param ghcrToken string

@description('App SECRETS as name->value (names from ENV_MATRIX.md). Wired as ACA secret refs; never committed.')
@secure()
param appSecrets object

@description('Non-secret app env as name->value.')
param appEnv object = {}

param owner string = 'wearthemood'
param costCenter string = 'wtm-prod'

// Six cron tasks + their five-field UTC schedules (finalized in Phase 4 §13.3).
param cronJobs array = [
  { name: 'news', command: 'app.tasks.news', cron: '0 */6 * * *' }
  { name: 'daily-push', command: 'app.tasks.daily', cron: '0 * * * *' }
  { name: 'backup', command: 'app.tasks.backup', cron: '30 2 * * *' }
  { name: 'spend-alert', command: 'app.tasks.spend_alert', cron: '15 */6 * * *' }
  { name: 'credit-reset', command: 'app.tasks.credit_reset', cron: '0 3 * * *' }
  { name: 'giveaway-chats', command: 'app.tasks.giveaway_chats', cron: '20 * * * *' }
]

@description('''
§13.3 — scheduled execution stays OFF until DO Ofelia is retired, otherwise both
platforms run the same cron against the same production DB (duplicate pushes,
duplicate backups, double credit-reset). ACA Jobs have no `enabled` flag, so a
never-firing expression (31 February) is the disable mechanism; the real schedules
above are still recorded in the job definition comment + Phase 4 report and are
applied by flipping this flag at Phase 6. Manual `az containerapp job start`
executions are unaffected — that is the approved way to test (§14.4).
''')
param cronSchedulesEnabled bool = false

@description('Recovery re-signals lost wake-ups; same duplicate-execution concern while the DO worker is live.')
param recoveryScheduleEnabled bool = false

// 31 Feb — syntactically valid, never fires.
var neverFires = '0 0 31 2 *'

@description('''
KEDA scale-down cooldown. Phase 5 §14.5 measured this as the DOMINANT Azure cost
driver: at 600s any arrival gap shorter than the cooldown pins a 2 vCPU / 4 GiB
replica on continuously, which bills ~$150/month against a $16.67/month ceiling —
while the actual work is only ~4.8 replica-seconds per job (~$7.56/month at 30k MAU).
Lowered to 60s, which takes beta load to $0/month. Scale-down granularity is still
the binding constraint above ~300 jobs/day; see PHASE_5_REPORT.md §5.
''')
param cooldownSeconds int = 60

var tags = {
  project: 'wear-the-mood'
  environment: 'prod'
  owner: owner
  costCenter: costCenter
}
var queueJobs = 'jobs'
var queueEnrichment = 'enrichment'

// ── identity: user-assigned MI for queue access + GHCR pull ──────────────────
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-id'
  location: location
  tags: tags
}

// ── storage: Standard_LRS + the two wake-signal queues ───────────────────────
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}
resource queueSvc 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storage
  name: 'default'
}
resource qJobs 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueSvc
  name: queueJobs
}
resource qEnrich 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueSvc
  name: queueEnrichment
}

// Storage Queue Data Contributor → the managed identity (least privilege for send/
// receive/delete). Role GUID 974c5e8b-45b9-4653-ba55-5f855dd0fb88.
resource queueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, uami.id, 'queue-data-contributor')
  scope: storage
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  }
}

// ── observability: Log Analytics (30-day max) + ACA Consumption env ──────────
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-logs'
  location: location
  tags: tags
  properties: {
    retentionInDays: logRetentionDays
    sku: { name: 'PerGB2018' }
  }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-env'
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

// Shared bits for every app/job container.
var identityId = uami.id
var queueEndpoint = storage.properties.primaryEndpoints.queue
var appEnvArr = [for k in items(appEnv): { name: k.key, value: string(k.value) }]
var baseEnv = concat([
  { name: 'QUEUE_PROVIDER', value: 'azure' }
  // REQUIRED for a *user-assigned* identity: bare DefaultAzureCredential() cannot pick
  // one on its own and dies with "Unable to load the proper Managed Identity". It reads
  // this variable to select the UAMI. Found by the Phase 4 §13.5 candidate test.
  { name: 'AZURE_CLIENT_ID', value: uami.properties.clientId }
  { name: 'AZURE_STORAGE_ACCOUNT_NAME', value: storageAccountName }
  { name: 'AZURE_STORAGE_QUEUE_ENDPOINT', value: queueEndpoint }
  { name: 'AZURE_QUEUE_JOBS', value: queueJobs }
  { name: 'AZURE_QUEUE_ENRICHMENT', value: queueEnrichment }
  { name: 'ENVIRONMENT', value: 'prod' }
], appEnvArr)
var secretRefs = [for s in items(appSecrets): { name: toLower(replace(s.key, '_', '-')), value: string(s.value) }]
var secretEnv = [for s in items(appSecrets): { name: s.key, secretRef: toLower(replace(s.key, '_', '-')) }]
var ghcrSecret = { name: 'ghcr-token', value: ghcrToken }
var allSecrets = concat(secretRefs, [ghcrSecret])
var registries = [{ server: 'ghcr.io', username: ghcrUsername, passwordSecretRef: 'ghcr-token' }]

// ── worker: rembg (2 vCPU / 4 GiB, 0–3, scale on `jobs`) ─────────────────────
resource rembg 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-rembg-worker'
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityId}': {} } }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: allSecrets
      registries: registries
    }
    template: {
      containers: [{
        name: 'rembg'
        image: rembgImage
        resources: { cpu: json('2.0'), memory: '4Gi' }
        env: concat(baseEnv, secretEnv)
      }]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        pollingInterval: 15
        cooldownPeriod: cooldownSeconds
        rules: [{
          name: 'jobs-queue'
          custom: {
            type: 'azure-queue'
            metadata: { accountName: storageAccountName, queueName: queueJobs, queueLength: '5', cloud: 'AzurePublicCloud' }
            identity: identityId
          }
        }]
      }
    }
  }
}

// ── worker: orchestrator (0.5 vCPU / 1 GiB, 0–3, scale on `enrichment`) ───────
resource orchestrator 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-ai-orchestrator'
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityId}': {} } }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: allSecrets
      registries: registries
    }
    template: {
      containers: [{
        name: 'orchestrator'
        image: orchestratorImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: concat(baseEnv, secretEnv)
      }]
      scale: {
        minReplicas: 0
        maxReplicas: 3
        pollingInterval: 15
        cooldownPeriod: cooldownSeconds
        rules: [{
          name: 'enrichment-queue'
          custom: {
            type: 'azure-queue'
            metadata: { accountName: storageAccountName, queueName: queueEnrichment, queueLength: '5', cloud: 'AzurePublicCloud' }
            identity: identityId
          }
        }]
      }
    }
  }
}

// ── emergency API (0–1, external ingress, disabled by app guard, no prod route) ─
resource emergency 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-api-emergency'
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityId}': {} } }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: allSecrets
      registries: registries
      ingress: { external: true, targetPort: 8000, transport: 'http' }
    }
    template: {
      containers: [{
        name: 'api'
        image: apiImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: concat(baseEnv, secretEnv, [
          { name: 'EMERGENCY_API', value: 'true' }
          { name: 'EMERGENCY_API_ENABLED', value: 'false' }
        ])
      }]
      scale: { minReplicas: 0, maxReplicas: 1 }
    }
  }
}

// ── recovery Job — every 5 minutes (§11.6) ───────────────────────────────────
resource recovery 'Microsoft.App/jobs@2024-10-02-preview' = {
  name: '${namePrefix}-recovery'
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityId}': {} } }
  properties: {
    environmentId: env.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 300
      scheduleTriggerConfig: {
        cronExpression: recoveryScheduleEnabled ? '*/5 * * * *' : neverFires
        parallelism: 1
        replicaCompletionCount: 1
      }
      secrets: allSecrets
      registries: registries
    }
    template: {
      containers: [{
        name: 'recovery'
        image: orchestratorImage
        command: ['python', '-m', 'app.tasks.recovery']
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: concat(baseEnv, secretEnv)
      }]
    }
  }
}

// ── six cron Jobs — created with a NEVER-FIRING schedule while DO Ofelia owns
//    cron (§13.3). Real target schedule per job is `j.cron`; applied at Phase 6 by
//    setting cronSchedulesEnabled=true. Test with `az containerapp job start`.
resource crons 'Microsoft.App/jobs@2024-10-02-preview' = [for j in cronJobs: {
  name: '${namePrefix}-cron-${j.name}'
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityId}': {} } }
  properties: {
    environmentId: env.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 1800
      scheduleTriggerConfig: {
        cronExpression: cronSchedulesEnabled ? j.cron : neverFires
        parallelism: 1
        replicaCompletionCount: 1
      }
      secrets: allSecrets
      registries: registries
    }
    template: {
      containers: [{
        name: j.name
        image: orchestratorImage
        command: ['python', '-m', j.command]
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: concat(baseEnv, secretEnv)
      }]
    }
  }
}]

output storageAccount string = storage.name
output managedIdentityClientId string = uami.properties.clientId
output emergencyFqdn string = emergency.properties.configuration.ingress.fqdn
