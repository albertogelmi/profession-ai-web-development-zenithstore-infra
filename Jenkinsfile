// =============================================================================
// ZenithStore — Pipeline CI/CD
// =============================================================================
//
// STRUTTURA WORKSPACE
//   /           ← repo infra  (checkout Jenkins SCM)
//   /app/       ← repo app    (checkout stage 'Checkout App')
//   /scripts/   ← script deploy
//   /docker/    ← compose files e configurazioni
//
// CREDENTIALS  (Gestisci Jenkins → Credenziali → Credenziali globali)
//   jwt-secret       Secret text  JWT_SECRET condiviso tra BE e FE
//   db-password      Secret text  MySQL root password
//   mongo-password   Secret text  MongoDB admin password
//   nextauth-secret  Secret text  NEXTAUTH_SECRET per NextAuth.js
//
// GLOBAL PROPERTIES  (Gestisci Jenkins → System → Global properties)
//   APP_REPO            URL del repository app
//                       default: https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git
//   NOTIFICATION_EMAIL  Indirizzo email per notifiche build
//                       default: team@zenithstore.com
//
// VARIABILI OPZIONALI  (Global properties o variabili del job)
//   BRANCH                   Branch da buildare (default: main)
//                              main               → deploy su develop    (automatico)
//                              release_candidate  → deploy su staging    (automatico)
//                              release            → deploy su production (approval manuale)
//   NEXT_PUBLIC_BACKEND_URL  URL pubblico del backend  (default: http://localhost)
//   NEXT_PUBLIC_WS_URL       URL WebSocket pubblico    (default: ws://localhost)
//   NEXT_PUBLIC_MOCK_PAYMENT "true" o "false"          (default: "true")
//
// ⚠️  CHECKLIST PRIMA DELLA PRIMA ESECUZIONE
//   [ ] Aggiungere le 4 Credentials elencate sopra
//   [ ] Impostare APP_REPO e NOTIFICATION_EMAIL in Global properties
//   [ ] Abilitare lo stage DB Migration quando le TypeORM migrations sono pronte
// =============================================================================

pipeline {
    agent any

    environment {
        APP_REPO   = "${env.APP_REPO   ?: 'https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git'}"
        BRANCH     = "${env.BRANCH    ?: 'main'}"
        BE_IMAGE   = 'zenithstore-backend'
        FE_IMAGE   = 'zenithstore-frontend'
        // COMMIT_SHA viene impostato dinamicamente nello stage Checkout (env.COMMIT_SHA)
        // Path del volume zenithstore-nginx-conf montato in questo container Jenkins.
        // Usato da switch-blue-green.sh e rollback.sh per aggiornare active.conf
        // senza dipendere da path host (vedi compose.monitoring.yml).
        NGINX_CONF_DIR = '/nginx-conf'
        // ── Notifiche email ───────────────────────────────────────────────────
        // Indirizzo destinatario delle notifiche build Jenkins.
        // Sovrascrivere in Manage Jenkins → Configure System → Global properties.
        NOTIFICATION_EMAIL = "${env.NOTIFICATION_EMAIL ?: 'team@zenithstore.com'}"
        // ── Frontend build args ───────────────────────────────────────────────
        // Valori di default per sviluppo locale. Sovrascrivere in produzione tramite
        // Manage Jenkins → Configure System → Global properties (o variabili del job).
        NEXT_PUBLIC_BACKEND_URL  = "${env.NEXT_PUBLIC_BACKEND_URL  ?: 'http://localhost'}"
        NEXT_PUBLIC_WS_URL       = "${env.NEXT_PUBLIC_WS_URL       ?: 'ws://localhost'}"
        NEXT_PUBLIC_MOCK_PAYMENT = "${env.NEXT_PUBLIC_MOCK_PAYMENT ?: 'true'}"
    }

    stages {

        // ── 1. CHECKOUT ───────────────────────────────────────────────────────
        stage('Checkout App') {
            steps {
                // Il repo infra è già presente nel workspace (checkout Jenkins SCM).
                // Qui si fa il checkout del repo app in una subdir dedicata.
                dir('app') {
                    git url: env.APP_REPO, branch: env.BRANCH
                }
                script {
                    env.COMMIT_SHA = sh(
                        script: 'git -C app rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.DEPLOY_ENV = (env.BRANCH == 'release')           ? 'production'
                                   : (env.BRANCH == 'release_candidate') ? 'staging'
                                   : 'develop'
                    echo "Branch: ${env.BRANCH} → Deploy target: ${env.DEPLOY_ENV} | Commit: ${env.COMMIT_SHA}"
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
                sh """
                    # Backend
                    docker build \
                        -t ${BE_IMAGE}:${env.COMMIT_SHA} \
                        -t ${BE_IMAGE}:latest \
                        app/backend/

                    # Frontend — NEXT_PUBLIC_* vars sono baked nel bundle client al momento della build.
                    # I valori vengono letti dalle variabili d'ambiente Jenkins (env block qui sopra);
                    # per ambienti diversi da localhost sovrascrivere le variabili a livello di job
                    # o in Manage Jenkins → Configure System → Global properties.
                    docker build \
                        -t ${FE_IMAGE}:${env.COMMIT_SHA} \
                        -t ${FE_IMAGE}:latest \
                        --build-arg NEXT_PUBLIC_BACKEND_URL=${env.NEXT_PUBLIC_BACKEND_URL} \
                        --build-arg NEXT_PUBLIC_WS_URL=${env.NEXT_PUBLIC_WS_URL} \
                        --build-arg NEXT_PUBLIC_MOCK_PAYMENT=${env.NEXT_PUBLIC_MOCK_PAYMENT} \
                        app/frontend/
                """
            }
        }

        // ── 5. DEPLOY ─────────────────────────────────────────────────────────
        // L'ambiente di destinazione è derivato dal branch (vedi stage Checkout):
        //   main               → develop    (automatico)
        //   release_candidate  → staging    (automatico)
        //   release            → production (richiede approval manuale)
        stage('Deploy') {
            steps {
                script {
                    if (env.DEPLOY_ENV == 'production') {
                        input message: "Deploy in produzione? (branch: ${env.BRANCH})", ok: 'Approva Deploy'
                    }
                }
                withCredentials([
                    string(credentialsId: 'jwt-secret',      variable: 'JWT_SECRET'),
                    string(credentialsId: 'db-password',     variable: 'DB_PASSWORD'),
                    string(credentialsId: 'mongo-password',  variable: 'MONGO_PASSWORD'),
                    string(credentialsId: 'nextauth-secret', variable: 'NEXTAUTH_SECRET'),
                ]) {
                    sh "bash scripts/switch-blue-green.sh deploy ${env.COMMIT_SHA} ${env.DEPLOY_ENV}"
                }
            }
        }
    }

    post {
        failure {
            script {
                try {
                    mail(
                        to: env.NOTIFICATION_EMAIL,
                        subject: "❌ FAIL: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        body: "Stage fallito. Vedere i log: ${env.BUILD_URL}"
                    )
                } catch (e) {
                    echo "⚠️ Notifica email non inviata (SMTP non configurato): ${e.message}"
                }
            }
        }
        success {
            script {
                try {
                    mail(
                        to: env.NOTIFICATION_EMAIL,
                        subject: "✅ OK: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        body: "Deploy completato.\nCommit: ${env.COMMIT_SHA}\nBuild: ${env.BUILD_URL}"
                    )
                } catch (e) {
                    echo "⚠️ Notifica email non inviata (SMTP non configurato): ${e.message}"
                }
            }
        }
    }
}
