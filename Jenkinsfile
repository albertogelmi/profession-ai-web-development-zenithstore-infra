// ─────────────────────────────────────────────────────────────────────────────
// ZenithStore — Pipeline CI/CD
// ─────────────────────────────────────────────────────────────────────────────
// Struttura workspace Jenkins:
//   /                    ← infra repo (questa Repo, già checkout da Jenkins SCM)
//   /app/                ← app repo  (checkout dallo stage 'Checkout App')
//   /scripts/            ← script deploy
//   /docker/             ← compose files e configurazioni
//
// Jenkins Credentials richieste (Manage Jenkins → Credentials):
//   jwt-secret       — JWT_SECRET condiviso tra BE e FE
//   db-password      — MySQL root password
//   mongo-password   — MongoDB admin password
//   nextauth-secret  — NEXTAUTH_SECRET per NextAuth.js
//   email-password   — Password SMTP per le notifiche Jenkins
//
// ⚠️  REMINDER — DA RIVEDERE PRIMA DELLA PRIMA ESECUZIONE:
//   - Aggiornare APP_REPO con l'URL reale del repository app
//   - Verificare gli indirizzi email nel blocco post {}
//   - Abilitare lo stage DB Migration una volta implementate le TypeORM migrations
//   - Verificare che Docker CLI sia disponibile nell'agente Jenkins
// ─────────────────────────────────────────────────────────────────────────────

pipeline {
    agent any

    environment {
        APP_REPO = 'https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git'
        BE_IMAGE = 'zenithstore-backend'
        FE_IMAGE = 'zenithstore-frontend'
        // COMMIT_SHA viene impostato dinamicamente nello stage Checkout (env.COMMIT_SHA)
        // Path del volume zenithstore-nginx-conf montato in questo container Jenkins.
        // Usato da switch-blue-green.sh e rollback.sh per aggiornare active.conf
        // senza dipendere da path host (vedi compose.monitoring.yml).
        NGINX_CONF_DIR = '/nginx-conf'
    }

    stages {

        // ── 1. CHECKOUT ───────────────────────────────────────────────────────
        stage('Checkout App') {
            steps {
                // Il repo infra è già presente nel workspace (checkout Jenkins SCM).
                // Qui si fa il checkout del repo app in una subdir dedicata.
                dir('app') {
                    git url: env.APP_REPO, branch: 'main'
                }
                script {
                    env.COMMIT_SHA = sh(
                        script: 'git -C app rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    echo "Commit SHA: ${env.COMMIT_SHA}"
                }
            }
        }

        // ── 2. BUILD ──────────────────────────────────────────────────────────
        // TODO: aggiungere path-filtering (changeset backend/** / frontend/**)
        //       una volta verificata la configurazione SCM multi-repo.
        //       Per ora si esegue sempre (safe default).
        stage('Build') {
            parallel {
                stage('Build Backend') {
                    steps {
                        dir('app/backend') {
                            sh 'npm ci'
                            sh 'npm run build'
                        }
                    }
                }
                stage('Build Frontend') {
                    steps {
                        dir('app/frontend') {
                            sh 'npm ci'
                            sh 'npm run build'
                        }
                    }
                }
            }
        }

        // ── 3. TEST ───────────────────────────────────────────────────────────
        stage('Test') {
            parallel {
                stage('Test Backend') {
                    steps {
                        dir('app/backend') {
                            sh 'npm run test:ci'
                        }
                    }
                    post {
                        always {
                            junit 'app/backend/test-results/junit.xml'
                        }
                    }
                }
                stage('Test Frontend') {
                    steps {
                        dir('app/frontend') {
                            sh 'npm run test:ci'
                        }
                    }
                    post {
                        always {
                            junit 'app/frontend/test-results/junit.xml'
                        }
                    }
                }
            }
        }

        // ── 3b. DB MIGRATION ──────────────────────────────────────────────────
        // Eseguire PRIMA del Docker Build per garantire che lo schema sia
        // aggiornato prima che qualsiasi container parta.
        // ⚠️  PLACEHOLDER: abilitare quando le TypeORM migrations sono create.
        stage('DB Migration') {
            steps {
                withCredentials([
                    string(credentialsId: 'db-password', variable: 'DB_PASSWORD'),
                ]) {
                    dir('app/backend') {
                        // Decommentare e sostituire con il comando migration reale:
                        // sh 'npm run typeorm -- migration:run'
                        echo 'DB Migration: placeholder — implementare TypeORM migrations e abilitare questo step'
                    }
                }
            }
        }

        // ── 4. DOCKER BUILD & TAG ─────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                withCredentials([
                    string(credentialsId: 'jwt-secret',      variable: 'JWT_SECRET'),
                    string(credentialsId: 'db-password',     variable: 'DB_PASSWORD'),
                    string(credentialsId: 'mongo-password',  variable: 'MONGO_PASSWORD'),
                    string(credentialsId: 'nextauth-secret', variable: 'NEXTAUTH_SECRET'),
                ]) {
                    sh """
                        # Backend
                        docker build \
                            -t ${BE_IMAGE}:${env.COMMIT_SHA} \
                            -t ${BE_IMAGE}:latest \
                            app/backend/

                        # Frontend — NEXT_PUBLIC_WS_URL punta a Nginx (:80) per il client browser.
                        # NEXT_PUBLIC_BACKEND_URL viene sovrascritto a runtime dal compose per il proxy server-side.
                        docker build \
                            -t ${FE_IMAGE}:${env.COMMIT_SHA} \
                            -t ${FE_IMAGE}:latest \
                            --build-arg NEXT_PUBLIC_BACKEND_URL=http://localhost \
                            --build-arg NEXT_PUBLIC_WS_URL=ws://localhost \
                            app/frontend/
                    """
                }
            }
        }

        // ── 5. DEPLOY STAGING (automatico) ───────────────────────────────────
        stage('Deploy Staging') {
            steps {
                withCredentials([
                    string(credentialsId: 'jwt-secret',      variable: 'JWT_SECRET'),
                    string(credentialsId: 'db-password',     variable: 'DB_PASSWORD'),
                    string(credentialsId: 'mongo-password',  variable: 'MONGO_PASSWORD'),
                    string(credentialsId: 'nextauth-secret', variable: 'NEXTAUTH_SECRET'),
                ]) {
                    sh "bash scripts/switch-blue-green.sh deploy ${env.COMMIT_SHA} staging"
                }
            }
        }

        // ── 6. DEPLOY PRODUCTION (manuale — approval gate) ───────────────────
        stage('Deploy Production') {
            input {
                message 'Deploy in produzione?'
                ok 'Approva Deploy'
            }
            steps {
                withCredentials([
                    string(credentialsId: 'jwt-secret',      variable: 'JWT_SECRET'),
                    string(credentialsId: 'db-password',     variable: 'DB_PASSWORD'),
                    string(credentialsId: 'mongo-password',  variable: 'MONGO_PASSWORD'),
                    string(credentialsId: 'nextauth-secret', variable: 'NEXTAUTH_SECRET'),
                ]) {
                    sh "bash scripts/switch-blue-green.sh deploy ${env.COMMIT_SHA} production"
                }
            }
        }
    }

    post {
        failure {
            mail(
                to: 'team@zenithstore.com',
                subject: "❌ FAIL: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Stage fallito. Vedere i log: ${env.BUILD_URL}"
            )
        }
        success {
            mail(
                to: 'team@zenithstore.com',
                subject: "✅ OK: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body: "Deploy completato.\nCommit: ${env.COMMIT_SHA}\nBuild: ${env.BUILD_URL}"
            )
        }
    }
}
