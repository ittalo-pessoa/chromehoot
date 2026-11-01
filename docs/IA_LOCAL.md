# Assistente de quizzes sem internet

O ChromeHoot gera sugestões usando **Ollama local**, com `qwen2.5:1.5b` como padrão inicial para o servidor Ubuntu com i5 e 8 GB de RAM. O modelo precisa ser medido nesse computador; não há garantia de latência ou qualidade pedagógica. Na configuração padrão, cada pedido contém de três a vinte questões com quatro alternativas. Tudo passa por revisão explícita do professor antes de virar um quiz.

Ollama **não estava instalado no ambiente desta implementação**. Os testes automatizados validaram a integração usando um servidor HTTP local controlado, não inferência real. Os comandos abaixo são necessários em cada máquina que vai gerar sugestões. O servidor de produção Ubuntu é separado do Windows/WSL de desenvolvimento; instalar no WSL não instala no servidor.

## Instalação automática no servidor Ubuntu

### Se você inicia o site com `rails s -b 0.0.0.0`

Esse comando, sem `RAILS_ENV` definido, usa **development**, mesmo em um servidor Ubuntu. Nesse caso, execute:

```sh
ruby script/setup_ai.rb --environment development
```

O script usa o banco/configuração de desenvolvimento da aplicação, não exige uma chave de produção, aplica a migration e configura a fila em **chromehoot-ai-development.service**, com variáveis em `/etc/chromehoot/ai-development.env`. Não compila assets de produção nesse modo e não altera a unidade/arquivo de variáveis da fila de produção. Reinicie seu Rails com Ctrl+C e `rails s -b 0.0.0.0` após terminar. Não execute simultaneamente o antigo `bin/rails ai:work` manual e o serviço gerenciado sem necessidade.

Por padrão o instalador continua usando `production`. A opção explícita evita trocar de banco apenas porque o terminal não carregou as variáveis. Usar development no servidor não equivale a configurar uma implantação de produção; essa migração deve ser planejada separadamente, preservando os dados existentes.


Depois de enviar esta atualização ao servidor, entre na pasta da aplicação **com o mesmo usuário, Ruby e variáveis de ambiente usados pelo deploy** e execute:

```sh
ruby script/setup_ai.rb
```

Não coloque `sudo` antes desse comando: o script pede sudo apenas para instalar pacotes e configurar os serviços, mantendo a fila com o usuário do deploy. Se você já faz o deploy como root, ele usa esse mesmo usuário. Execute fora de uma partida, pois instala/configura serviços e faz uma geração de diagnóstico.

O script tenta recuperar a configuração existente do próprio ChromeHoot em produção (processos Ruby/Puma/Passenger no diretório da aplicação e arquivos `.env.production.local`, `.env.production`, `.env`, `shared/.env.production`, `shared/.env` ou `config/.env.production`). Não mostra valores, não gera outra chave e não copia variáveis de processos de outros projetos. Se houver configurações diferentes, pede apenas que você escolha um número; um `.env` sem indicação de produção também exige confirmação. A recuperação depende de o processo/arquivo conter as variáveis; configurações exclusivas de contêineres, nginx/Apache ou outros formatos podem exigir `--env-file`.

O script confere o ambiente de produção e a conexão PostgreSQL antes de instalar; instala ferramentas ausentes e o Ollama oficial se necessário; configura a API apenas em loopback com nuvem desativada; baixa `qwen2.5:1.5b` se ausente; aplica migrations; compila assets; cria e inicia **chromehoot-ai.service**; e executa o diagnóstico real. A instalação inicial precisa de internet e pode demorar devido ao download. Se houver erro ao iniciar o Rails, ele distingue chave ausente, credenciais criptografadas, autenticação/conexão PostgreSQL, gems/Ruby e permissões, exibindo um resumo seguro com código e presença das variáveis (sem seus valores). Envie apenas esse resumo ao pedir ajuda. Se houver erro, ele interrompe e informa a etapa; a configuração pode estar parcial e o script pode ser executado novamente após corrigir a causa.

Se seu deploy usa um arquivo privado de variáveis que não estão carregadas no terminal:

```sh
ruby script/setup_ai.rb --env-file /CAMINHO/PRIVADO/chromehoot.env
```

O arquivo deve conter uma variável literal `KEY=valor` por linha, podendo usar aspas. Não use `export`, substituição de comandos, expansão de variáveis ou valores em várias linhas. O script lê como dados, sem executar código shell. Ele grava uma cópia normalizada para a fila em `/etc/chromehoot/ai.env`, com acesso restrito a root; não mostra os segredos na saída. Sem `--env-file`, preserva essa configuração se já existir, ou captura as variáveis de banco/segredo reconhecidas no ambiente atual. Alterações posteriores nos segredos do deploy precisam ser reaplicadas com `--env-file` apontando para a configuração atualizada.

Por padrão ele não tenta adivinhar qual é o serviço web. Reinicie a aplicação pelo método habitual após a instalação, ou informe o nome correto para o script reiniciar automaticamente:

```sh
ruby script/setup_ai.rb --env-file /CAMINHO/PRIVADO/chromehoot.env --app-service NOME_DO_SERVICO_WEB
```

Outras opções:

```sh
ruby script/setup_ai.rb --dry-run          # apenas descreve, não altera nada
ruby script/setup_ai.rb --skip-diagnose    # instala sem gerar o quiz de diagnóstico
ruby script/setup_ai.rb --help
sudo journalctl -u chromehoot-ai -f       # acompanhar pedidos e erros da fila
```

O script requer Ubuntu/Linux com **systemd ativo**, autorização sudo (ou root), dependências Ruby já instaladas da aplicação e acesso ao banco de produção. No WSL sem systemd, use os passos manuais abaixo. O script instala os serviços apenas na máquina onde é executado, não se conecta automaticamente ao servidor remoto.

A execução completa do instalador com downloads e alterações em `/etc` não foi realizada no ambiente de desenvolvimento desta implementação. Foram verificados sintaxe, modo de simulação, tratamento de variáveis privadas e geração da unidade systemd por testes automatizados. O resultado do diagnóstico real deve ser conferido no servidor após executar.

## 1. Instalar no Ubuntu (produção) ou dentro do WSL (teste)

A instalação e o primeiro download exigem internet. Consulte a [instalação oficial Linux](https://docs.ollama.com/linux). Baixe e confira o instalador oficial antes de executá-lo:

```sh
curl -fsSL https://ollama.com/install.sh -o /tmp/chromehoot-ollama-install.sh
less /tmp/chromehoot-ollama-install.sh
sh /tmp/chromehoot-ollama-install.sh
ollama --version
```

Com systemd disponível, configure o serviço local:

```sh
sudo systemctl edit ollama
```

Inclua:

```ini
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_NO_CLOUD=1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_CONTEXT_LENGTH=4096"
Environment="OLLAMA_KEEP_ALIVE=0"
```

Depois:

```sh
sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo systemctl enable ollama
ollama pull qwen2.5:1.5b
ollama list
curl --fail http://127.0.0.1:11434/api/tags
```

Se o WSL não tiver systemd, mantenha um terminal com o processo abaixo e execute o `ollama pull` em outro terminal. Não inicie uma segunda instância se já existe uma ouvindo na porta 11434:

```sh
OLLAMA_HOST=127.0.0.1:11434 OLLAMA_NO_CLOUD=1 OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_CONTEXT_LENGTH=4096 OLLAMA_KEEP_ALIVE=0 ollama serve
```

Instale o Ollama dentro do mesmo Ubuntu/WSL onde o Rails roda, para ambos acessarem o loopback. Se a produção usa contêiner, o loopback é o do contêiner; essa topologia exige configuração adicional e não foi validada. Não exponha a porta 11434 aos alunos ou à internet.

Não há API paga nem fallback para nuvem. O cliente Rails aceita apenas `http://127.0.0.1`, `http://localhost` ou `http://[::1]`, com a porta configurada. Não segue redirects e não usa proxy HTTP do ambiente. O serviço Ollama também precisa ter `OLLAMA_NO_CLOUD=1`. Nenhum pedido da interface baixa modelos automaticamente.

## 2. Atualizar a aplicação e iniciar a fila

Nesta atualização **há uma migration** para `ai_quiz_drafts`. No servidor, faça o deploy habitual e execute:

```sh
RAILS_ENV=production bin/rails db:migrate
RAILS_ENV=production bin/rails assets:precompile
```

Configure estas variáveis no processo Rails e no processo da fila (os valores abaixo já são os padrões):

```sh
OLLAMA_URL=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:1.5b
```

Reinicie os processos da aplicação depois do deploy. É necessário um processo separado para executar os pedidos, usando a mesma versão do código, ambiente, banco e credenciais do Rails:

```sh
# Produção:
RAILS_ENV=production bin/rails ai:work

# Desenvolvimento dentro do WSL, em outro terminal:
bin/rails ai:work
```

O site permanece disponível enquanto o processo de IA espera a resposta. A fila fica no PostgreSQL e os pedidos sobrevivem a recarregamentos e reinícios. Sem o processo `ai:work`, os pedidos ficam na fila; iniciar apenas `ollama serve` não executa a fila da aplicação.

Para produção, supervisione esse processo. Exemplo systemd, adaptando usuário, diretórios, caminho do Bundler e arquivo privado de variáveis ao deploy real:

```ini
[Unit]
Description=ChromeHoot - fila de IA local
After=network.target postgresql.service ollama.service

[Service]
Type=simple
User=USUARIO_DA_APLICACAO
WorkingDirectory=/CAMINHO/DO/CHROMEHOOT
Environment=RAILS_ENV=production
EnvironmentFile=/CAMINHO/PRIVADO/chromehoot.env
ExecStart=/CAMINHO/DO/RUBY/bin/bundle exec rake ai:work
Restart=on-failure
RestartSec=5
TimeoutStopSec=780

[Install]
WantedBy=multi-user.target
```

O arquivo de variáveis precisa definir as mesmas credenciais do banco/segredo da aplicação e o ambiente Ruby correspondente. Não copie valores literais de exemplo para produção. O tratamento de TERM/INT permite concluir a solicitação em andamento antes de encerrar; se o processo for interrompido à força, a próxima execução identifica pedidos em processamento e os marca como falha, permitindo novo pedido.

## 3. Usar pela interface

1. Entre como professor e abra **Assistente de IA** no menu ou **Criar quiz com IA local** no painel.
2. Informe tema, disciplina, série, dificuldade e três a vinte questões.
3. Aguarde a geração. Pode sair e voltar em **Meus últimos pedidos**; os rascunhos são privados.
4. Revise título, descrição, enunciados, quatro alternativas, tempo e alternativa correta. Não trate a resposta da IA como fonte confiável por si só.
5. Marque **Revisei os enunciados, as alternativas e o gabarito** e clique em **Salvar quiz revisado**.
6. O quiz salvo usa os mesmos formulários, snapshots e partidas existentes. A partir daí, jogar não depende de Ollama.

Não são enviados nomes, e-mails, respostas ou dados dos alunos ao modelo: somente tema, disciplina, série, dificuldade e quantidade. Os textos não são comandos executáveis. Os JSONs são validados quanto a formato, limites, quantidade, alternativas diferentes e gabarito único antes de salvar. Isso valida a estrutura, não a correção dos fatos. Importação é transacional e repetir o salvamento não duplica o quiz.

## 4. Limites para 8 GB de RAM

- Uma geração global por vez, protegida por bloqueio consultivo PostgreSQL, inclusive com múltiplos processos de fila.
- Um pedido pendente por professor; até oito tentativas por professor em 15 minutos.
- Novas gerações aguardam na fila enquanto existir partida em estado `running`. Uma geração que já começou pode continuar caso um professor inicie uma partida; prepare os quizzes antes da aula.
- Contexto de 4096 tokens, até 2500 tokens de saída e dois threads de CPU por requisição; esses valores são um ponto inicial, não desempenho medido.
- Limite total de três minutos por lote, conexão de cinco segundos e resposta limitada a 128 KiB. Erros e JSON incompleto ficam visíveis no pedido, sem salvar quiz parcial.
- `keep_alive: 0` solicita descarregar o modelo após a geração. O limite do cliente não é garantia de cancelamento imediato do cálculo no servidor Ollama; monitore seu processo em caso de timeout.

## 5. Validar o modelo real e o modo offline

Com Ollama rodando e o modelo instalado, dentro do diretório da aplicação:

```sh
# Desenvolvimento:
bin/rails runner script/check_ai.rb

# Produção:
RAILS_ENV=production bin/rails runner script/check_ai.rb
```

Esse diagnóstico faz uma geração real, mede a duração, valida a estrutura e escreve `tmp/ai-smoke-test.json`, sem criar um quiz no banco. Revise o gabarito e registre o resultado, a versão obtida com `ollama --version`, o i5 exato e o consumo de memória observado. Execute fora de partidas e sem outros pedidos em geração: o diagnóstico é direto e não passa pela fila.

Confira a liberação de memória com `ollama ps` após a resposta e uso do servidor com `free -h`/`top`. Desconecte o acesso externo mantendo a rede local ativa e repita uma geração pela UI. Faça uma aula de teste antes de considerar o recurso validado nesse servidor.

Os testes automatizados disponíveis são:

```sh
bin/rails test
```

Eles cobrem conexão HTTP local, schema/options/keep_alive enviados, modelo ausente, JSON malformado, resposta grande, rejeição de endereço remoto, fila e falha recuperável, revisão, permissões e salvamento idempotente. Não medem a qualidade ou o tempo de um modelo real.

Referências: [API chat](https://docs.ollama.com/api/chat), [saída estruturada](https://docs.ollama.com/capabilities/structured-outputs), [configuração e memória](https://docs.ollama.com/faq), [modelo Qwen2.5](https://ollama.com/library/qwen2.5).

## Quizzes com até 20 questões

O professor pode escolher de 3 a 20 questões. A geração usa lotes sequenciais de até 5, enviando um resumo dos enunciados anteriores para evitar repetição. Não salva conteúdo parcial: qualquer falha exige novo pedido. Ao terminar, todas as questões aparecem na mesma revisão. O prazo de 3 minutos vale por lote; 20 questões podem exigir quatro lotes e até aproximadamente 12 minutos. A correção factual e repetições semânticas continuam dependendo da revisão do professor.

Esta ampliação exige nova migration. Reexecute o instalador no mesmo ambiente do site (por exemplo `ruby script/setup_ai.rb --environment development`), que aplica a migration e atualiza o prazo de parada do serviço para 780 segundos. Não foi medida a duração real de vinte questões no i5/8 GB.

## Se apareceu “bad unit file setting” na fila

Uma versão anterior do instalador gerava aspas indevidas em `WorkingDirectory` e `EnvironmentFile`. O Ollama e o modelo podiam instalar normalmente, mas a fila não iniciava. Após atualizar o código, reexecute `ruby script/setup_ai.rb --environment development` (ou o ambiente correto do site). A unidade será corrigida e validada com `systemd-analyze verify` antes da instalação. O modelo já baixado é reaproveitado. O aviso de CPU-only não é essa falha de configuração.

## Remover pedidos indesejados

Cada pedido em Meus últimos pedidos e na própria tela tem botão Excluir com confirmação. Pedidos em fila são removidos antes da geração. Em processamento, o cálculo atual no Ollama pode terminar, mas o resultado não é salvo e nenhum lote seguinte é solicitado. A exclusão não apaga um quiz já importado. Apenas o dono pode excluir. Pedidos pendentes não são a causa de erro de sintaxe da unidade systemd.
