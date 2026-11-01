# ChromeHoot

Quiz educacional para a rede local da escola, implementado na aplicação Rails existente, sem executar `rails new`. Interface em português, HTML/ERB, Turbo, Stimulus, polling HTTP e Active Storage em disco. Não utiliza CDN, fontes remotas, serviços externos nem WebSocket nas partidas.

## Ambiente verificado

- Ruby **3.1.0**, Bundler **2.6.5**, Rails **7.2.4** (resolvido no `Gemfile.lock`), PostgreSQL **12.22**, Puma **8.0.2**.
- Mantida a linha Rails 7.2 compatível com a aplicação e o Ruby existentes. Documentação consultada: [migrations 7.2](https://guides.rubyonrails.org/v7.2/active_record_migrations.html) e [Active Storage 7.2](https://guides.rubyonrails.org/v7.2/active_storage_overview.html).
- **Limitação do ambiente herdado:** Ruby 3.1 e PostgreSQL 12 estão fora de manutenção; o Brakeman instalado também sinaliza fim de suporte do Rails 7.2. Atualize e revalide a pilha antes de operação regular. Este trabalho validou o fluxo local nessas versões, não uma implantação de produção. Consulte [manutenção Rails](https://rubyonrails.org/maintenance) e [ciclo de versões Ruby](https://www.ruby-lang.org/en/downloads/branches/).

## Preparação

Instale previamente Ruby compatível, Bundler e PostgreSQL com headers de desenvolvimento (`libpq-dev` no Ubuntu). PostgreSQL deve estar iniciado. Crie um usuário PostgreSQL local com permissão de criar os bancos de desenvolvimento e teste ou configure `DATABASE_URL`; não use o superusuário do banco em operação regular.

```sh
bundle install
bin/rails db:prepare
```

`config/database.yml` usa `chromehoot_development` e `chromehoot_test`, via socket e usuário local por padrão. `DATABASE_URL` pode configurar conexão e credenciais sem versionar segredos. O arquivo `.env.example` é apenas referência; não é carregado automaticamente.

Professores podem criar a própria conta em **Área do professor → Criar conta de professor** (`/signup`), informando nome, e-mail, senha com pelo menos 12 caracteres e confirmação. O cadastro entra diretamente no painel pessoal. Cada professor continua acessando apenas seus quizzes, partidas e relatórios. Não há verificação do e-mail por envio de mensagem.

Para criar a conta pelo terminal e, opcionalmente, o quiz original com cinco questões:

```sh
read -r -p 'E-mail do professor: ' TEACHER_EMAIL
read -r -s -p 'Senha (mínimo de 12 caracteres): ' TEACHER_PASSWORD
export TEACHER_EMAIL TEACHER_PASSWORD
TEACHER_NAME='Professor' DEMO_SEED=1 bin/rails db:seed
unset TEACHER_EMAIL TEACHER_PASSWORD
```

O seed é idempotente. Omita `DEMO_SEED=1` para criar apenas a conta; mantenha dados demonstrativos fora da base de produção. Executar novamente com o mesmo e-mail define a senha informada. Contas adicionais usam o mesmo procedimento com outros e-mails.

## Interface responsiva

O painel do professor usa menu lateral em telas grandes e navegação horizontal em telas pequenas. Entrada, controle, questões, placar e relatórios se reorganizam para celular, tablet e computador, com recursos visuais locais. O resumo final do aluno mostra acertos, posição, pontos e desempenho individual por questão; o relatório usa gráficos calculados dos registros reais.

## Abrir e jogar

```sh
bin/rails server -b 0.0.0.0 -p 3000
```

No servidor, abra **http://localhost:3000**. Professor: “Área do professor”, entrar, criar quiz, adicionar questões com duas a cinco alternativas e uma correta. Crie uma sala, compartilhe o código de seis dígitos e abra a projeção em outra janela.

Alunos acessam **http://IP_LOCAL_DO_SERVIDOR:3000** na mesma rede, informam código e apelido. `localhost` nos Chromebooks aponta para o próprio Chromebook. Descubra o IP do notebook com `hostname -I` no Linux ou `ipconfig` no Windows. Não é necessário acesso à internet após instalar as dependências.

Inicie a partida, abra a questão, feche as respostas, revele o resultado e avance. Cada próxima questão aguarda abertura explícita. O prazo é decidido pelo servidor; uma resposta aceita não pode ser trocada. Quando todos os participantes ativos respondem, as respostas são encerradas automaticamente, sem esperar o tempo acabar. Participantes removidos não bloqueiam esse encerramento; a revelação continua sendo feita pelo professor e a pontuação mantém o prazo original. Finalizar fecha uma rodada aberta e libera os resultados das rodadas fechadas na mesma transação. Cancelar encerra sem liberar novos resultados. O relatório do professor contém todas as respostas persistidas, erros, ausências e CSV seguro para planilhas. Arquivar o quiz preserva as partidas.

O cookie assinado e HttpOnly recupera a participação ao atualizar/reabrir o navegador por até dois dias, enquanto preservado. Apelido e código não recuperam identidade. Ao informar outro código na página inicial, o navegador entra na nova sala e substitui a credencial anterior apenas se a entrada for aceita. A recuperação automática ocorre somente para o mesmo código de uma partida ainda ativa. Um código já encerrado pede uma nova partida. “Sair desta participação” descarta a credencial atual. Participantes removidos mantêm o histórico. A sessão do professor expira após 12 horas.

O aluno consulta o estado a cada 2 segundos durante uma questão e a cada 4 segundos na espera; o controle consulta a cada 2 segundos. As consultas não se sobrepõem, têm limite de espera e param ao encerrar/desconectar a tela. O relógio visual usa o horário do servidor. Gabarito, acerto individual e pontuação só são enviados após revelação. O placar público inclui apenas rodadas reveladas.

## Música opcional nas perguntas

Em **Editar informações** do quiz, envie a música em MP3, OGG, WAV ou M4A (até 15 MB), salve e crie uma **nova sala**. O áudio é copiado para a partida, servido pelo Active Storage local e incluído no backup de arquivos. Alterar o quiz não muda a música de uma sala já criada. Não foi incluída a gravação de Super Mario World: é necessário fornecer o arquivo desejado.

Na sala, clique em **Ativar música** no navegador que deverá tocar o som (por exemplo, apenas na projeção do professor). O som começa em 8% e pode ser ajustado até 20% ou silenciado. Só toca durante perguntas abertas, pausa no encerramento das respostas/prazo, na finalização e ao sair da tela. O navegador pode exigir nova interação para liberar a reprodução; a interface trata esse bloqueio sem interromper o jogo. Sem áudio enviado, a partida continua normalmente e não exibe controles musicais.

## Validação

```sh
bin/rails db:test:prepare
bin/rails test
node test/javascript/music_controller_test.mjs
RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop
bundle exec brakeman --no-pager
```

O script original `bin/brakeman` exige a versão mais recente da ferramenta e pode parar antes da análise em um ambiente sem atualização. O comando acima executa a versão instalada; os alertas de dependências fora de manutenção não foram suprimidos.

Carga HTTP real (banco de **teste**, sem `DATABASE_URL`; não execute junto da suíte):

```sh
RAILS_ENV=test bin/rails server -b 127.0.0.1 -p 3100 -P tmp/pids/load-test.pid
# Outro terminal:
bundle exec ruby script/load_test.rb
```

Cria e remove apenas os dados próprios do ensaio. Usa 50 clientes concorrentes, 350 requisições, polling aberto/final e dois envios por aluno; escreve métricas em `tmp/load-test.json`. Não mede Wi-Fi, Chromebooks, renderização nem digitação. Veja [resultados por etapa e limitações](docs/VALIDACAO.md) e [métricas registradas](docs/load-test-2026-11-01.json).

## Rede da escola e execução regular

Confira firewall do notebook (liberar TCP 3000 apenas na rede local), isolamento de clientes no roteador e redes de convidados. Não exponha a porta 5432 aos alunos. Mantenha notebook ligado, suspensão automática desativada durante partidas e rede local ativa.

Windows: prefira WSL2. Em redes WSL com NAT pode ser necessário encaminhar a porta do Windows para o IP atual do WSL e liberar o firewall do Windows, além de iniciar Rails em `0.0.0.0`. O modo de rede espelhada depende da versão do Windows/WSL. Valide o endereço a partir de outro dispositivo; liberar somente o processo Rails não garante conectividade. Não foi testado Windows/WSL neste ambiente Linux.

Desenvolvimento serve à validação local. Operação regular requer versões mantidas, ambiente `production`, `SECRET_KEY_BASE` privado e estável, banco próprio, assets pré-compilados (`RAILS_ENV=production bin/rails assets:precompile`), Puma supervisionado (por exemplo, systemd), proxy HTTPS local com certificado confiável nos Chromebooks, firewall e backups. O modo production mantém HTTPS obrigatório. Não desative HTTPS silenciosamente para contornar sua configuração. Não há publicação ou hospedagem externa configurada.

## Backup e recuperação

Pare os comandos de jogo e uploads (preferencialmente pare o Rails) para obter banco e arquivos do mesmo instante. Proteja o diretório de backup e mantenha cópia fora do notebook. Exemplos com conexão já configurada no ambiente PostgreSQL:

```sh
pg_dump -Fc -d chromehoot_production -f /CAMINHO_SEGURO/chromehoot.dump
tar -czf /CAMINHO_SEGURO/chromehoot-storage.tgz storage
```

Guarde também `SECRET_KEY_BASE`/chave mestra de forma segura, separada dos arquivos públicos. Para recuperar, use banco **novo e separado**, nunca sobrescreva o atual como teste:

```sh
createdb chromehoot_restore
pg_restore --no-owner -d chromehoot_restore /CAMINHO_SEGURO/chromehoot.dump
# Em uma cópia separada da aplicação:
tar -xzf /CAMINHO_SEGURO/chromehoot-storage.tgz -C /CAMINHO_DA_COPIA
# Inicie a cópia com DATABASE_URL apontando somente para chromehoot_restore.
```

Verifique login, relatório, total de respostas e imagem na cópia antes de considerar a recuperação concluída. Ajuste permissões de `storage/` para o usuário do processo. O script abaixo executa uma recuperação automática isolada, com banco, snapshots, resposta, pontuação e imagem conferida por SHA-256, e remove seus dois bancos temporários (requer permissão de criar bancos):

```sh
bundle exec ruby script/verify_backup.rb
```
