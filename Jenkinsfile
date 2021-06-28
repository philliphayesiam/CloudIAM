pipeline {
  agent any
  stages {
    stage('Stage 1') {
      parallel {
        stage('Stage 1') {
          agent any
          steps {
            echo 'hello BOcean'
            sh '''touch /tmp/run1
echo "stage 1" >> /tmp/run1'''
          }
        }

        stage('SubStage1') {
          steps {
            echo 'Hellosubstage1'
          }
        }

      }
    }

    stage('Stage 2') {
      steps {
        echo 'Hello BOcean2'
      }
    }

  }
}