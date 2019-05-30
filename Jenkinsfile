pipeline {
  agent {
    label 'linuxKernel'
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '2'))
  }

  stages {
    stage('Deploy') {
      steps {
        withCredentials(bindings: [usernamePassword(credentialsId: 'github_credentials', 
        			usernameVariable: 'USERNAME', 
        			passwordVariable: 'PASSWORD')]) {
          sh './make_var_mx6ul_dart_debian.sh -c deploy -u $USERNAME -p $PASSWORD'
        }
      }
    }

    stage('Update') {
      steps {
        withCredentials(bindings: [usernamePassword(credentialsId: 'github_credentials', 
        			usernameVariable: 'USERNAME', 
        			passwordVariable: 'PASSWORD')]) {
          sh './make_var_mx6ul_dart_debian.sh -c update'
        }

      }
    }

    stage('Cleanup') {
      steps {
        sh 'sudo ./make_var_mx6ul_dart_debian.sh -c clean'
      }
    }

    stage('Build Kernel and package') {
      stages {
        stage('Aventura') {
          steps {
            sh 'sudo ./make_var_mx6ul_dart_debian.sh -c package -t twonav-aventura-2018'
          }
        }
        stage('Trail') {
          steps {
            sh 'sudo ./make_var_mx6ul_dart_debian.sh -c package -t twonav-trail-2018'
          }
        }
      }
    }
  }

  post {
    success {
      echo 'Save Artifacts'
      archiveArtifacts artifacts: 'output/*.deb', onlyIfSuccessful: true
    }

    always {
      echo 'Pipeline finished.'
    }
  }
}
