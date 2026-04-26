package test

import (
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	awsRegion   = "us-east-1"
	clusterName = "aegis-test"
)

func TestEKSClusterSecurity(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../../infrastructure",
		Vars: map[string]interface{}{
			"cluster_name":           clusterName,
			"environment":            "test",
			"grafana_admin_password": "test-only",
		},
		EnvVars: map[string]string{"AWS_DEFAULT_REGION": awsRegion},
	})
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	require.NotEmpty(t, clusterEndpoint)

	t.Run("SecretsEncryptionEnabled", func(t *testing.T) {
		cluster := aws.GetEksCluster(t, awsRegion, clusterName)
		require.NotNil(t, cluster.EncryptionConfig, "EKS secrets encryption must be configured")
		assert.Contains(t, cluster.EncryptionConfig[0].Resources, "secrets")
	})

	t.Run("PrivateEndpointOnly", func(t *testing.T) {
		cluster := aws.GetEksCluster(t, awsRegion, clusterName)
		assert.False(t, *cluster.ResourcesVpcConfig.EndpointPublicAccess)
		assert.True(t, *cluster.ResourcesVpcConfig.EndpointPrivateAccess)
	})

	t.Run("ControlPlaneLoggingEnabled", func(t *testing.T) {
		cluster := aws.GetEksCluster(t, awsRegion, clusterName)
		require.NotNil(t, cluster.Logging)
		var enabled []string
		for _, lc := range cluster.Logging.ClusterLogging {
			if lc.Enabled != nil && *lc.Enabled {
				for _, lt := range lc.Types {
					enabled = append(enabled, string(lt))
				}
			}
		}
		assert.Contains(t, enabled, "audit")
		assert.Contains(t, enabled, "api")
	})

	t.Run("GatekeeperRunning", func(t *testing.T) {
		kubectlOpts := k8s.NewKubectlOptionsFromKubeconfig(t, clusterName, awsRegion)
		retry.DoWithRetry(t, "Wait for Gatekeeper", 20, 15*time.Second, func() (string, error) {
			pods, err := k8s.ListPodsE(t, kubectlOpts, metav1.ListOptions{
				LabelSelector: "control-plane=controller-manager",
				Namespace:     "gatekeeper-system",
			})
			if err != nil || len(pods) == 0 {
				return "", fmt.Errorf("gatekeeper not ready yet")
			}
			for _, pod := range pods {
				if !k8s.IsPodAvailable(&pod) {
					return "", fmt.Errorf("pod %s not available", pod.Name)
				}
			}
			return "ready", nil
		})
	})

	t.Run("PrivilegedPodRejected", func(t *testing.T) {
		kubectlOpts := k8s.NewKubectlOptionsFromKubeconfig(t, clusterName, awsRegion)
		content := `apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: secure-apps
spec:
  containers:
    - name: test
      image: alpine:3.18.5
      securityContext:
        privileged: true`
		f := writeTempFile(t, "priv-pod.yaml", content)
		_, err := k8s.RunKubectlAndGetOutputE(t, kubectlOpts, "apply", "-f", f)
		assert.Error(t, err, "privileged pod should be rejected")
	})

	t.Run("LatestTagPodRejected", func(t *testing.T) {
		kubectlOpts := k8s.NewKubectlOptionsFromKubeconfig(t, clusterName, awsRegion)
		content := `apiVersion: v1
kind: Pod
metadata:
  name: test-latest-tag
  namespace: secure-apps
spec:
  containers:
    - name: test
      image: alpine:latest
      securityContext:
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]`
		f := writeTempFile(t, "latest-pod.yaml", content)
		_, err := k8s.RunKubectlAndGetOutputE(t, kubectlOpts, "apply", "-f", f)
		assert.Error(t, err, "latest tag pod should be rejected")
	})
}

func writeTempFile(t *testing.T, name, content string) string {
	t.Helper()
	f, err := os.CreateTemp("", name)
	require.NoError(t, err)
	_, err = f.WriteString(content)
	require.NoError(t, err)
	require.NoError(t, f.Close())
	t.Cleanup(func() { os.Remove(f.Name()) })
	return f.Name()
}
