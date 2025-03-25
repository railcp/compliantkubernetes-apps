# grafana-org-operator

![Version: 0.0.1](https://img.shields.io/badge/Version-0.0.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.1](https://img.shields.io/badge/AppVersion-0.0.1-informational?style=flat-square)

Grafana Org Operator

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.repository | string | `"registry.gitlab.com/kubitus-project/grafana-org-operator"` |  |
| image.tag | string | `"latest"` |  |
| replicas | int | `1` |  |
| resources.limits.cpu | string | `"500m"` |  |
| resources.limits.memory | string | `"128Mi"` |  |
| resources.requests.cpu | string | `"5m"` |  |
| resources.requests.memory | string | `"64Mi"` |  |
| serviceMonitor.enabled | bool | `false` |  |
| serviceMonitor.labels | object | `{}` |  |
| grafanaOrgOperatorControllerManagerDeployment | object | `{}` |  |
| grafanaOrgOperatorControllerManagerMetricsMonitorServicemonitor | object | `{}` |  |
| grafanaOrgOperatorControllerManagerMetricsServiceSvc | object | `{}` |  |
| grafanaOrgOperatorControllerManagerSa | object | `{}` |  |
| grafanaOrgOperatorGrafanainstanceEditorRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanainstanceViewerRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanaorgEditorRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanaorgViewerRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanaorgdashboardEditorRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanaorgdashboardViewerRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanaorgdatasourceEditorRoleCr | object | `{}` |  |
| grafanaOrgOperatorGrafanaorgdatasourceViewerRoleCr | object | `{}` |  |
| grafanaOrgOperatorLeaderElectionRoleRole | object | `{}` |  |
| grafanaOrgOperatorLeaderElectionRolebindingRb | object | `{}` |  |
| grafanaOrgOperatorManagerRoleCr | object | `{}` |  |
| grafanaOrgOperatorManagerRolebindingCrb | object | `{}` |  |
| grafanaOrgOperatorMetricsAuthRoleCr | object | `{}` |  |
| grafanaOrgOperatorMetricsAuthRolebindingCrb | object | `{}` |  |
| grafanaOrgOperatorMetricsReaderCr | object | `{}` |  |
| grafanaOrgOperatorSystemNamespace | object | `{}` |  |
| grafanainstancesGrafanaOrgOperatorKubitusProjectGitlabIoCrd | object | `{}` |  |
| grafanaorgdashboardsGrafanaOrgOperatorKubitusProjectGitlabIoCrd | object | `{}` |  |
| grafanaorgdatasourcesGrafanaOrgOperatorKubitusProjectGitlabIoCrd | object | `{}` |  |
| grafanaorgsGrafanaOrgOperatorKubitusProjectGitlabIoCrd | object | `{}` |  |
