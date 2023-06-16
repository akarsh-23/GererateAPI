pipeline {
  agent any
  
  tools {nodejs "NodeJS"}
  
  stages {
    stage('Checkout') {
      steps {
        git branch: 'main', url: 'https://github.com/akarsh-23/GererateAPI.git'
      }
    }
    
    stage('Linting and Code Quality') {
      steps {
        sh 'npm install' // Install dependencies
        sh 'npm run lint' // Run linting
      }
    }
    
    stage('Provision Infrastructure') {
      steps {
        sh 'terraform apply --auto-approve'
      }
    }
    
    stage('Build and Push Docker Image') {
      steps {
        sh 'aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 393079086060.dkr.ecr.ap-south-1.amazonaws.com'
        sh 'docker build -t generate-api-ecr-repo .'
        sh 'docker tag generate-api-ecr-repo 393079086060.dkr.ecr.ap-south-1.amazonaws.com/generate-api-ecr-repo:latest'
        sh 'docker push 393079086060.dkr.ecr.ap-south-1.amazonaws.com/generate-api-ecr-repo:latest'
      }
    }
    
    stage('Deploy to ECS (Blue-Green)') {
      steps {
        sh 'aws deploy create-deployment --application-name generate-api-codedeploy-app --deployment-group-name generate-api-codedeploy-deployment-group --revision "{\"revisionType\":\"S3\",\"s3Location\":{\"bucket\":\"generate-api-bucket\",\"key\":\"appspec.json\",\"bundleType\":\"JSON\"}}"'
      }
    }
  }
}

