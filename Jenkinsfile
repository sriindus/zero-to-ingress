// Declarative pipeline: test -> build image -> push -> deploy to Kubernetes.
// All tooling used here is open source (Jenkins, Kaniko/Docker, kubectl, kustomize).
pipeline {
  agent any

  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
  }

  environment {
    REGISTRY     = 'ghcr.io'
    IMAGE_OWNER  = 'sriindus'                     // GitHub user/org that owns the package
    IMAGE_NAME   = 'hello-world-frontend'
    IMAGE_REPO   = "${REGISTRY}/${IMAGE_OWNER}/${IMAGE_NAME}"
    IMAGE_TAG    = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : env.BUILD_NUMBER}"
    K8S_NAMESPACE = 'hello-world'
    // Jenkins credentials IDs — create these in Manage Jenkins > Credentials
    REGISTRY_CREDENTIALS = 'ghcr-credentials'  // username + PAT with write:packages
    KUBECONFIG_CREDENTIAL = 'kubeconfig'       // secret file
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          env.IMAGE_TAG = env.GIT_SHA
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Install & Test') {
      agent {
        docker {
          image 'node:22-alpine'
          reuseNode true
          args '-u root:root'
        }
      }
      steps {
        dir('app') {
          sh '''
            set -eu
            if [ -f package-lock.json ]; then npm ci; else npm install --no-audit --no-fund; fi
            npm test
          '''
        }
      }
    }

    stage('Lint Manifests') {
      steps {
        sh '''
          set -eu
          if command -v kubectl >/dev/null 2>&1; then
            kubectl kustomize k8s/ > /dev/null
            echo "manifests render cleanly"
          else
            echo "kubectl not available on this agent; skipping manifest render"
          fi
        '''
      }
    }

    stage('Build & Push Image') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: env.REGISTRY_CREDENTIALS,
          usernameVariable: 'REGISTRY_USER',
          passwordVariable: 'REGISTRY_PASS'
        )]) {
          sh '''
            set -eu
            echo "$REGISTRY_PASS" | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
            docker build \
              --build-arg BUILDKIT_INLINE_CACHE=1 \
              -t "$IMAGE_REPO:$IMAGE_TAG" \
              -t "$IMAGE_REPO:latest" \
              -f Dockerfile .
            docker push "$IMAGE_REPO:$IMAGE_TAG"
            docker push "$IMAGE_REPO:latest"
            docker logout "$REGISTRY"
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      when {
        branch 'main'
      }
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CREDENTIAL, variable: 'KUBECONFIG_FILE')]) {
          sh '''
            set -eu
            export KUBECONFIG="$KUBECONFIG_FILE"

            cd k8s
            kustomize edit set image "$IMAGE_REPO=$IMAGE_REPO:$IMAGE_TAG"
            cd ..

            kubectl apply -k k8s/
            kubectl -n "$K8S_NAMESPACE" rollout status deployment/hello-world-frontend --timeout=180s
          '''
        }
      }
    }

    stage('Smoke Test') {
      when {
        branch 'main'
      }
      steps {
        withCredentials([file(credentialsId: env.KUBECONFIG_CREDENTIAL, variable: 'KUBECONFIG_FILE')]) {
          sh '''
            set -eu
            export KUBECONFIG="$KUBECONFIG_FILE"
            kubectl -n "$K8S_NAMESPACE" run smoke-$BUILD_NUMBER \
              --image=curlimages/curl:8.11.1 --rm -i --restart=Never --quiet -- \
              -fsS http://hello-world-frontend.$K8S_NAMESPACE.svc.cluster.local/api/hello
          '''
        }
      }
    }
  }

  post {
    success {
      echo "Deployed ${env.IMAGE_REPO}:${env.IMAGE_TAG}"
    }
    failure {
      echo "Build failed — see the stage logs above."
    }
    always {
      sh 'docker image prune -f --filter "until=24h" || true'
      cleanWs()
    }
  }
}
