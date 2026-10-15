# Démarrage Docker

La configuration actuelle utilise trois modèles partagés ; suivre aussi
[l'installation multi-LLM](MULTI_LLM.md) pour télécharger les deux modèles Qwen.

Lancer Docker Desktop en mode conteneurs Linux. Godot reste sur Windows ;
Ollama et le service Python tournent dans Docker. Python et Ollama n'ont pas
besoin d'être installés sur Windows pour ce démarrage.

Depuis la racine du projet :

```powershell
# Facultatif : conserver le fichier existant s'il est déjà présent.
if (!(Test-Path .env)) { Copy-Item .env.example .env }
docker compose up -d ollama
# Téléchargement explicite du modèle lors de la première installation :
docker compose run --rm model-pull
docker compose up -d --build ai-service
docker compose ps
Invoke-RestMethod http://127.0.0.1:8765/health
```

Ouvrir project.godot, F5, Start simulation puis Launch nuke. Le statut attendu
est CONNECTED. Les démarrages suivants utilisent `docker compose up -d`.

## Configuration et stockage

Le modèle par défaut est llama3.2:1b. Les modèles sont conservés dans le volume
ollama_models, distinct de l'installation Ollama de Windows. Aucun modèle
n'est téléchargé au démarrage normal. Pour changer le modèle, modifier
OLLAMA_MODEL dans .env, relancer `docker compose run --rm model-pull` puis
`docker compose up -d ai-service`.

Godot utilise toujours http://127.0.0.1:8765. Le service Python utilise
http://ollama:11434 sur le réseau Docker : Compose impose cette adresse,
même si .env contient l'adresse localhost destinée à l'ancien lancement.
Le port Ollama n'est pas publié sur Windows. Les autres paramètres d'inférence
de .env sont transmis au service. Le port public reste fixé à 8765.

Les traces Python sont conservées dans outputs/ai_backend_runs sur Windows.
Les traces Godot restent dans outputs/ai_runs. Le service utilise un seul
worker et conserve l'inférence séquentielle ; Docker n'ajoute pas de parallélisme.

## GPU NVIDIA facultatif

La configuration de base utilise le CPU. Pour utiliser un GPU NVIDIA compatible,
ajouter `-f compose.yaml -f compose.gpu.yaml` à toutes les commandes Compose :

```powershell
docker compose -f compose.yaml -f compose.gpu.yaml up -d ollama
docker compose -f compose.yaml -f compose.gpu.yaml run --rm model-pull
docker compose -f compose.yaml -f compose.gpu.yaml up -d --build ai-service
```

Sous Windows, cela nécessite Docker Desktop avec WSL2 et les pilotes NVIDIA
compatibles. Cette option n'est pas destinée aux GPU AMD ou Intel. Le mode CPU
peut être plus lent qu'une installation Ollama Windows utilisant déjà le GPU.
Voir la [documentation Docker GPU](https://docs.docker.com/compose/how-tos/gpu-support/).

## Diagnostic et arrêt

```powershell
docker compose logs -f ai-service ollama
docker compose exec ollama ollama list
docker compose exec ollama ollama ps
docker compose stop
# Supprime les conteneurs et le réseau, mais conserve les modèles :
docker compose down
```

Ne pas utiliser down -v sauf pour supprimer aussi les modèles.
MODEL_UNAVAILABLE signifie que le modèle configuré doit être téléchargé.
DISCONNECTED signifie qu'il faut vérifier le conteneur Ollama et ses logs.
Le contrôle de santé devient valide après le téléchargement du modèle.
Si le port 8765 est occupé, arrêter l'ancien service Python avant le lancement.
Les anciens scripts start_ai.cmd, start_ai.ps1 et check_ollama.ps1 sont remplacés
par les commandes Compose. Les scripts de génération audio restent disponibles.
