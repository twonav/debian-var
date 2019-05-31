pipeline {
  agent {
    label 'linuxKernel'
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '2'))
  }

  environment {
    PRODUCT_AVENTURA = 'twonav-aventura-2018'
    PRODUCT_TRAIL = 'twonav-trail-2018'
    AVENTURA_OUTPUT_DIR = 'output-aventura'
    TRAIL_OUTPUT_DIR = 'output-trail'
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

    stage('Build Kernel and package') {
      stages {
        stage('Cleanup Aventura') {
          steps {
            sh 'sudo ./make_var_mx6ul_dart_debian.sh -c clean'
          }
        }
        stage('Kernel Aventura') {
          steps {
            sh 'sudo ./make_var_mx6ul_dart_debian.sh -c package -t $PRODUCT_AVENTURA -o $AVENTURA_OUTPUT_DIR'
          }
        }
        stage('Cleanup Trail') {
          steps {
            sh 'sudo ./make_var_mx6ul_dart_debian.sh -c clean'
          }
        }
        stage('Kernel Trail') {
          steps {
            sh 'sudo ./make_var_mx6ul_dart_debian.sh -c package -t $PRODUCT_TRAIL -o $TRAIL_OUTPUT_DIR'
          }
        }
      }
    }
  }

  post {
    success {
      echo 'Save Artifacts'
      archiveArtifacts artifacts: '$AVENTURA_OUTPUT_DIR/*.deb,$TRAIL_OUTPUT_DIR/*.deb', onlyIfSuccessful: true
    }

    always {
      echo 'Pipeline finished.'
    }
  }
}
