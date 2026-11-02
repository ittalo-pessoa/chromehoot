# Geração de quizzes com Groq

O ChromeHoot usa a API HTTPS da Groq com `openai/gpt-oss-20b`, no lugar do Ollama. Não baixa modelos e não precisa de GPU. O servidor precisa de internet para gerar questões; os alunos e as partidas com quizzes já salvos continuam usando apenas a rede local.

## Configurar ou atualizar o servidor Ubuntu

1. Crie uma conta e uma chave em https://console.groq.com/keys. Mantenha a organização no **Free Plan**, sem ativar o plano pago. A gratuidade tem cotas por organização, minuto e dia, que podem mudar. Consulte https://console.groq.com/settings/limits. O aplicativo não ativa cobrança nem muda de provedor quando a cota acaba; mostra um erro para tentar após a renovação. O código não consegue verificar o plano de faturamento da conta: use uma chave de organização gratuita.
2. Envie a versão nova do projeto ao servidor pelo seu procedimento habitual.
3. Na pasta da aplicação, com o mesmo usuário e Ruby do site, execute **um** dos comandos:

```sh
# Site iniciado por rails s -b 0.0.0.0 sem RAILS_ENV:
ruby script/setup_ai.rb --environment development

# Site configurado em production:
ruby script/setup_ai.rb
```

Não coloque sudo antes. O script pede sudo apenas nas operações de sistema. Se faltar a chave, solicita que você a cole com entrada oculta. Ela é gravada no arquivo privado da fila, nunca no navegador ou no repositório:

- development: `/etc/chromehoot/ai-development.env`, serviço `chromehoot-ai-development`;
- production: `/etc/chromehoot/ai.env`, serviço `chromehoot-ai`.

O script reaproveita a configuração do banco, remove as variáveis antigas `OLLAMA_*` da configuração gerenciada, instala certificados HTTPS apenas se necessário, aplica migrations, compila assets em produção e substitui a unidade da fila sem dependência do Ollama. Faz uma geração real de diagnóstico com três questões, usando a cota da conta. Pode ser executado novamente; use `--skip-diagnose` para pular o diagnóstico. Execute fora de uma geração/partida.

Se as credenciais do deploy estão em outro arquivo privado:

```sh
ruby script/setup_ai.rb --environment production --env-file /CAMINHO/PRIVADO/chromehoot.env
```

Esse arquivo pode incluir `GROQ_API_KEY=...`, além das variáveis de banco/segredo existentes. Valores são dados literais `KEY=valor`, não comandos shell. Não troque as credenciais do banco nem gere outra chave Rails. Para substituir a chave da API, edite o arquivo privado com `sudoedit /etc/chromehoot/ai.env` (ou `ai-development.env`) e reinicie a fila. Não envie a chave pelo chat.

4. Reinicie o site pelo método habitual. Se usa `rails s`, encerre com Ctrl+C e inicie novamente. Para o instalador reiniciar um serviço web, informe `--app-service NOME_REAL_DO_SERVICO`.
5. Confira a fila e os logs, usando o serviço do seu ambiente:

```sh
# Development
sudo systemctl status chromehoot-ai-development --no-pager
sudo journalctl -u chromehoot-ai-development -n 50 --no-pager

# Production
sudo systemctl status chromehoot-ai --no-pager
sudo journalctl -u chromehoot-ai -n 50 --no-pager
```

6. Faça um **novo pedido** de 10 questões pela interface. Pedidos que já falharam não são retomados. Revise as questões e o gabarito antes de salvar.

O Ollama instalado anteriormente não é usado nem removido pelo instalador. Se nenhum outro aplicativo o utiliza, você pode parar seu serviço para liberar memória:

```sh
sudo systemctl disable --now ollama
```

Não é necessário apagar os modelos para o ChromeHoot funcionar.

## Execução manual, sem systemd

No terminal da fila, configure a chave sem colocá-la no histórico (Bash):

```bash
read -rsp 'GROQ_API_KEY: ' GROQ_API_KEY; echo
export GROQ_API_KEY
# Use o mesmo RAILS_ENV e banco do site:
bin/rails ai:work
# Ou, em produção:
RAILS_ENV=production bin/rails ai:work
```

Não execute simultaneamente essa fila manual e o serviço gerenciado sem necessidade. Rails não carrega `.env` automaticamente. Só o processo da fila e o diagnóstico precisam da chave.

## Funcionamento e limites

A geração solicita todas as 3–20 questões em uma chamada, usando JSON estruturado. A aplicação ainda valida quantidade, limites de texto, alternativas distintas, enunciados distintos e índice da resposta correta. Se faltarem questões válidas, preserva as aceitas e faz uma única chamada para completar as restantes. Se a Groq recusar o formato estruturado, há uma única tentativa de compatibilidade em modo JSON para aquela chamada, com o mesmo modelo e a mesma validação local. O prazo total de 120 segundos é compartilhado entre todas as chamadas. Não salva um quiz parcial nem repete automaticamente erros de cota, autenticação ou rede. O tempo real depende do provedor e da conexão; um teste real de dez questões levou cerca de um segundo neste ambiente, sem garantia de duração para outros pedidos ou servidores.

A dificuldade tem instruções próprias: fácil para conceitos básicos, média para aplicação/comparação e difícil para análise/resolução de problemas. Isso não garante qualidade factual: a revisão do professor permanece obrigatória.

A fila existente no PostgreSQL é preservada. Há uma geração por vez e novos pedidos aguardam durante partidas em andamento. Ao excluir um pedido, a chamada em andamento pode terminar, mas seu resultado não é salvo e não há chamada de correção.

São enviados tema, disciplina, série, dificuldade, quantidade e, quando necessário, enunciados aceitos para evitar repetição. Não são enviados nomes, e-mails ou respostas dos alunos. O conteúdo passa pelo provedor externo; consulte a política de dados da conta. A chave é enviada somente no cabeçalho Authorization ao destino HTTPS fixo `api.groq.com`; erros não exibem o corpo retornado pelo provedor.

## Diagnóstico e falhas

O instalador já executa `script/check_ai.rb` usando o arquivo privado correto. Para executá-lo manualmente, carregue as mesmas variáveis da fila no terminal e use:

```sh
RAILS_ENV=production bin/rails runner script/check_ai.rb
```

Use `RAILS_ENV=development` se esse for o ambiente do site. O diagnóstico cria `tmp/ai-smoke-test.json`, sem salvar quiz no banco. Execute sem outra geração para evitar disputar a cota.

- **Configure GROQ_API_KEY:** a chave falta no processo da fila; execute o instalador no ambiente correto.
- **Chave/acesso recusado:** confira a chave e a permissão para o modelo no painel da Groq.
- **Limite gratuito atingido:** confira os limites da organização e aguarde sua renovação. Fazer pedidos repetidos não resolve uma cota esgotada.
- **Não foi possível acessar a Groq:** confira DNS, certificados e saída HTTPS na porta 443 para `api.groq.com`.
- **Resposta incompleta ou inválida:** faça novo pedido; confira também a disponibilidade do modelo. Não há fallback para APIs pagas.

Referências oficiais: [plano gratuito e limites](https://console.groq.com/docs/rate-limits), [modelos](https://console.groq.com/docs/models), [JSON estruturado](https://console.groq.com/docs/structured-outputs), [primeiros passos](https://console.groq.com/docs/quickstart), [dados](https://console.groq.com/docs/your-data).
