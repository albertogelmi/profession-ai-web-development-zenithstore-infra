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
//   Per ogni ambiente creare 4 credenziali Secret text con suffisso
//   -development / -staging / -production (12 credenziali in totale):
//
//   jwt-secret-development       JWT Secret condiviso tra BE e FE (develop)
//   jwt-secret-staging           JWT Secret condiviso tra BE e FE (staging)
//   jwt-secret-production        JWT Secret condiviso tra BE e FE (production)
//   db-password-development      MySQL root password (develop)
//   db-password-staging          MySQL root password (staging)
//   db-password-production       MySQL root password (production)
//   mongo-password-development   MongoDB admin password (develop)
//   mongo-password-staging       MongoDB admin password (staging)
//   mongo-password-production    MongoDB admin password (production)
//   nextauth-secret-development  NEXTAUTH_SECRET per NextAuth.js (develop)
//   nextauth-secret-staging      NEXTAUTH_SECRET per NextAuth.js (staging)
//   nextauth-secret-production   NEXTAUTH_SECRET per NextAuth.js (production)
//
// GLOBAL PROPERTIES  (Gestisci Jenkins → System → Global properties → Variabili d'ambiente)
//
//   ── Repository ──────────────────────────────────────────────────────────────
//   APP_REPO                         URL del repository app
//                                    default nel codice: https://github.com/albertogelmi/...app.git
//
//   ── Notifiche email ─────────────────────────────────────────────────────────
//   NOTIFICATION_EMAIL_DEVELOPMENT   Email team sviluppo   (es. dev@zenithstore.com)
//   NOTIFICATION_EMAIL_STAGING       Email team QA          (es. qa@zenithstore.com)
//   NOTIFICATION_EMAIL_PRODUCTION    Email team ops         (es. ops@zenithstore.com)
//
//   ── Frontend build args (3 ambienti × 3 variabili = 9 properties) ──────────
//   NEXT_PUBLIC_BACKEND_URL_DEVELOPMENT    URL backend develop    (default: http://localhost)
//   NEXT_PUBLIC_BACKEND_URL_STAGING        URL backend staging    (es. https://staging-api.zenithstore.com)
//   NEXT_PUBLIC_BACKEND_URL_PRODUCTION     URL backend prod       (es. https://api.zenithstore.com)
//   NEXT_PUBLIC_WS_URL_DEVELOPMENT         WebSocket develop      (default: ws://localhost)
//   NEXT_PUBLIC_WS_URL_STAGING             WebSocket staging      (es. wss://staging.zenithstore.com)
//   NEXT_PUBLIC_WS_URL_PRODUCTION          WebSocket prod         (es. wss://zenithstore.com)
//   NEXT_PUBLIC_MOCK_PAYMENT_DEVELOPMENT   Mock pagamenti develop (default: "true")
//   NEXT_PUBLIC_MOCK_PAYMENT_STAGING       Mock pagamenti staging (default: "true")
//   NEXT_PUBLIC_MOCK_PAYMENT_PRODUCTION    Mock pagamenti prod    (default: "false")
//
// PARAMETRI PIPELINE  (disponibili con "Costruisci con parametri")
//   Branch   Rilevante solo per lanci manuali. Per i lanci automatici via webhook
//            il trigger SCM imposta GIT_BRANCH che ha priorità assoluta su questo parametro.
//              main               → deploy su develop    (automatico)
//              release-candidate  → deploy su staging    (automatico)
//              release            → deploy su production (approval manuale)
//
// ⚠️  CHECKLIST PRIMA DELLA PRIMA ESECUZIONE
//   [ ] Creare le 12 Credentials elencate sopra (4 segreti × 3 ambienti)
//   [ ] Impostare le 13 Global Properties elencate sopra (APP_REPO + 3 email + 9 NEXT_PUBLIC_*)
//   [ ] Configurare il job per monitorare i branch: */main, */release-candidate, */release
//   [ ] Abilitare lo stage DB Migration quando le TypeORM migrations sono pronte
// =============================================================================

pipeline {
    agent any

    parameters {
        choice(
            name: 'Branch',
            choices: ['main', 'release-candidate', 'release'],
            description: '''Rilevante solo per lanci manuali ("Costruisci con parametri").
Per i lanci automatici via webhook il branch viene rilevato dal trigger SCM e questo campo viene ignorato.

  main → deploy in develop
  release-candidate → deploy in staging
  release → deploy in production  ⚠ richiede approval manuale'''
        )
    }

    environment {
        // APP_REPO: letta da Global Properties; se non configurata usa il default.
        APP_REPO       = "${env.APP_REPO ?: 'https://github.com/albertogelmi/profession-ai-web-development-zenithstore-app.git'}"
        // BRANCH: se il trigger è SCM (GIT_BRANCH presente e riconosciuto) ha priorità assoluta.
        // Solo per lanci manuali (GIT_BRANCH assente o non riconosciuto) si usa params.Branch.
        BRANCH         = "${['main', 'release-candidate', 'release'].contains(env.GIT_BRANCH?.replaceFirst('origin/', '')) ? env.GIT_BRANCH.replaceFirst('origin/', '') : params.Branch}"
        BE_IMAGE       = 'zenithstore-backend'
        FE_IMAGE       = 'zenithstore-frontend'
        // Usato da switch-blue-green.sh e rollback.sh per aggiornare active.conf
        // nel volume zenithstore-nginx-conf montato in questo container Jenkins.
        NGINX_CONF_DIR = '/nginx-conf'
        // DEPLOY_ENV, COMMIT_SHA e ENV_SUFFIX vengono impostati dinamicamente
        // nello stage 'Checkout App' (vedi script block).
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
                    env.DEPLOY_ENV = (env.BRANCH == 'release')            ? 'production'
                                   : (env.BRANCH == 'release-candidate')  ? 'staging'
                                   : 'develop'
                    // ENV_SUFFIX: suffisso maiuscolo per Global Properties e Credentials.
                    // Mapping: develop → DEVELOPMENT, staging → STAGING, production → PRODUCTION.
                    env.ENV_SUFFIX = (env.DEPLOY_ENV == 'develop') ? 'DEVELOPMENT'
                                   : env.DEPLOY_ENV.toUpperCase()
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

        // ── 4. DB MIGRATION ───────────────────────────────────────────────────
        // Eseguire PRIMA del Docker Build per garantire che lo schema sia
        // aggiornato prima che qualsiasi container parta.
        // ⚠️  PLACEHOLDER: abilitare quando le TypeORM migrations sono create.
        stage('DB Migration') {
            steps {
                script {
                    def credSuffix = (env.DEPLOY_ENV == 'develop') ? 'development' : env.DEPLOY_ENV
                    withCredentials([
                        string(credentialsId: "db-password-${credSuffix}", variable: 'DB_PASSWORD'),
                    ]) {
                        dir('app/backend') {
                            // Decommentare e sostituire con il comando migration reale:
                            // sh 'npm run typeorm -- migration:run'
                            echo 'DB Migration: placeholder — implementare TypeORM migrations e abilitare questo step'
                        }
                    }
                }
            }
        }

        // ── 5. DOCKER BUILD & TAG ─────────────────────────────────────────────
        // Le variabili NEXT_PUBLIC_* sono baked nel bundle client al momento della
        // build. I valori vengono letti dalle Global Properties per ambiente
        // (es. NEXT_PUBLIC_BACKEND_URL_DEVELOPMENT): garantisce che ogni ambiente
        // abbia URL corretti senza ricompilare a runtime.
        stage('Docker Build') {
            steps {
                script {
                    def backendUrl  = env."NEXT_PUBLIC_BACKEND_URL_${env.ENV_SUFFIX}"  ?: 'http://localhost'
                    def wsUrl       = env."NEXT_PUBLIC_WS_URL_${env.ENV_SUFFIX}"       ?: 'ws://localhost'
                    def mockPayment = env."NEXT_PUBLIC_MOCK_PAYMENT_${env.ENV_SUFFIX}" ?: 'false'

                    sh """
                        # Backend
                        docker build \
                            -t ${env.BE_IMAGE}:${env.COMMIT_SHA} \
                            -t ${env.BE_IMAGE}:latest \
                            app/backend/

                        # Frontend — NEXT_PUBLIC_* sono baked nel bundle: ogni ambiente
                        # richiede un'immagine compilata con i propri URL specifici.
                        docker build \
                            -t ${env.FE_IMAGE}:${env.COMMIT_SHA} \
                            -t ${env.FE_IMAGE}:latest \
                            --build-arg NEXT_PUBLIC_BACKEND_URL=${backendUrl} \
                            --build-arg NEXT_PUBLIC_WS_URL=${wsUrl} \
                            --build-arg NEXT_PUBLIC_MOCK_PAYMENT=${mockPayment} \
                            app/frontend/
                    """
                }
            }
        }

        // ── 6. DEPLOY ─────────────────────────────────────────────────────────
        // L'ambiente di destinazione è derivato dal branch (vedi stage Checkout):
        //   main               → develop    (automatico)
        //   release-candidate  → staging    (automatico)
        //   release            → production (richiede approval manuale)
        stage('Deploy') {
            steps {
                script {
                    if (env.DEPLOY_ENV == 'production') {
                        input message: "Deploy in produzione? (branch: ${env.BRANCH})", ok: 'Approva Deploy'
                    }
                    def credSuffix = (env.DEPLOY_ENV == 'develop') ? 'development' : env.DEPLOY_ENV
                    withCredentials([
                        string(credentialsId: "jwt-secret-${credSuffix}",      variable: 'JWT_SECRET'),
                        string(credentialsId: "db-password-${credSuffix}",     variable: 'DB_PASSWORD'),
                        string(credentialsId: "mongo-password-${credSuffix}",  variable: 'MONGO_PASSWORD'),
                        string(credentialsId: "nextauth-secret-${credSuffix}", variable: 'NEXTAUTH_SECRET'),
                    ]) {
                        sh "bash scripts/switch-blue-green.sh deploy ${env.COMMIT_SHA} ${env.DEPLOY_ENV}"
                    }
                }
            }
        }
    }

    post {
        failure {
            script {
                try {
                    def emailVar  = "NOTIFICATION_EMAIL_${env.ENV_SUFFIX ?: 'DEVELOPMENT'}"
                    def recipient = env."${emailVar}" ?: 'team@zenithstore.com'
                    mail(
                        to: recipient,
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
                    def emailVar  = "NOTIFICATION_EMAIL_${env.ENV_SUFFIX ?: 'DEVELOPMENT'}"
                    def recipient = env."${emailVar}" ?: 'team@zenithstore.com'
                    mail(
                        to: recipient,
                        subject: "✅ OK: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        body: "Deploy completato.\nBranch: ${env.BRANCH} → ${env.DEPLOY_ENV}\nCommit: ${env.COMMIT_SHA}\nBuild: ${env.BUILD_URL}"
                    )
                } catch (e) {
                    echo "⚠️ Notifica email non inviata (SMTP non configurato): ${e.message}"
                }
            }
        }
    }
}
