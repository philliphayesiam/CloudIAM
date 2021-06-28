pipeline {
  agent any
  stages {
    stage('Stage 1') {
      agent any
      steps {
        echo 'hello BOcean'
        sh '''!/bin/bash

touch /tmp/run1'''
      }
    }

    stage('Stage 2') {
      steps {
        echo 'Hello BOcean2'
      }
    }

  }
}