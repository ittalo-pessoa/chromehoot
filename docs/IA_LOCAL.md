# A geração de quizzes mudou para IA online

O Ollama foi substituído pela API Groq, sem download de modelos. Siga [a configuração atual e os passos de migração do servidor](IA_ONLINE.md).

O comando continua sendo `ruby script/setup_ai.rb` em produção ou `ruby script/setup_ai.rb --environment development` para site iniciado em desenvolvimento. Agora ele solicita uma `GROQ_API_KEY`, configura a fila existente e não instala Ollama. A geração precisa de internet no servidor; partidas com quizzes já salvos continuam funcionando na rede local.
