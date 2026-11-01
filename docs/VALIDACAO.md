# Registro de implementação e validação

Data: 01/11/2026. Ambiente Linux local. Aplicação existente preservada; nenhuma execução de `rails new`, SQLite ou hospedagem externa.

## Etapas

1. **Base:** autenticação `has_secure_password`, com cadastro público de professor adicionado por solicitação posterior; sessão assinada com expiração, CSRF, logout, layout local e limitação de tentativas por e-mail. Validado por integração com login inválido, login válido, expiração/proteção de acesso e logout. A suíte verifica acesso protegido; a expiração é aplicada no filtro de autenticação.
2. **Conteúdo:** CRUD de quizzes, arquivamento, duplicação, editor de duas a cinco alternativas, validação da questão completa, ordenação e imagens locais limitadas a 5 MB (PNG/JPEG/WebP). Validados editor HTTP, ordenação, duplicação, quiz vazio/sem correta/com várias corretas e rejeição de SVG.
3. **Partida:** snapshots imutáveis pelo modelo, cópia da imagem via blob local, código aleatório de seis dígitos com zeros preservados, espera, apelido normalizado único e credencial aleatória com digest. Entrada só enquanto aguardando; remoção mantém histórico. Validados snapshots após edição, imagem após remover vínculo do original, código inválido/repetido/encerrado e cookie recuperado sem duplicação.
4. **Jogo:** serviços transacionais com bloqueio consistente partida→rodada, prazo do servidor, fechamento tardio idempotente, pontuação e resposta única. Polling Stimulus sem sobreposição, reconexão, comandos e projeção autenticada. Validada partida completa por HTTP com professor e dois navegadores lógicos, além de conexões PostgreSQL concorrentes para resposta duplicada e corrida fechar/responder. Repetir avanço com a rodada anterior já avançada não cria outra rodada.
5. **Resultados:** revelação explícita, ranking com empate por pontos/acertos/tempo correto, pódio, histórico, ausências e CSV com neutralização de fórmulas. Finalizar fecha e revela rodadas fechadas na mesma transação. Validados ocultação dos resultados no estado aberto/fechado, ranking, empate compartilhado e conteúdo do CSV.
6. **Validação:** suíte PostgreSQL, carga HTTP com 50 participantes, recursos locais e restauração isolada executadas. Roteiro físico de Wi-Fi, testes de navegador e acessibilidade manual permanecem para o ambiente escolar.

## Comandos e evidências

- `bin/rails db:migrate`: migrations executadas no PostgreSQL real, incluindo Active Storage, chaves estrangeiras, índices únicos e checks.
- `bin/rails test`: **49 testes, 456 verificações, zero falhas, zero erros, zero testes ignorados**. Inclui serviços, integrações, concorrência e idempotência dos seeds.
- `bin/rails zeitwerk:check`: carregamento de classes aprovado.
- `RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop`: código Ruby verificado.
- `node --input-type=module --check < app/javascript/controllers/game_controller.js`: sintaxe JavaScript verificada.
- `bundle exec brakeman --no-pager`: sem alertas de código da aplicação; dois alertas de dependências fora de manutenção (Ruby 3.1 e Rails 7.2). Não equivale a uma auditoria completa. `bin/brakeman` original exige atualização e recusou executar por não ser a versão mais recente; análise feita diretamente com a gem instalada.
- `bundle exec ruby script/verify_backup.rb`: recuperação aprovada em dois bancos descartáveis separados; professor, quiz, snapshot, participante, resposta, pontos e imagem conferidos. Arquivo recuperado conferido por SHA-256. Os bancos do ensaio bem-sucedido são removidos ao final.
- Integração solicita CSS, todos os módulos do importmap e imagem a partir da própria aplicação, conferindo resposta e conteúdo da imagem. Não houve bloqueio físico da conexão externa; essa evidência comprova URLs locais, não o funcionamento de Chromebooks em uma rede desconectada real.

## Carga HTTP real

Puma em modo test, um processo com três threads, PostgreSQL local, 50 clientes HTTP concorrentes no mesmo computador. Sem renderização de navegador. CSRF fica desativado no ambiente test, como na configuração Rails padrão; sua rejeição é validada separadamente na suíte. Sem cache externo.

| Operação | Requisições | Mediana | p95 | Máximo |
|---|---:|---:|---:|---:|
| Entrada | 50 | 535,56 ms | 770,22 ms | 811,91 ms |
| Estado durante questão | 150 | 400,71 ms | 735,25 ms | 775,35 ms |
| Resposta e reenvio | 100 | 672,63 ms | 801,81 ms | 815,95 ms |
| Estado final e placar | 50 | 554,34 ms | 1.051,04 ms | 1.090,49 ms |

Total: **350 requisições, zero erros, 50 respostas persistidas para 100 envios**. A soma de pontos do ranking coincidiu com a soma das respostas salvas. [JSON completo](load-test-2026-11-01.json). O ensaio usa rajadas simultâneas, não uma aula prolongada; não garante desempenho na infraestrutura escolar.

## Limitações e roteiro escolar pendente

Não havia Chrome/Chromium/Firefox neste ambiente. Testes HTTP não executam o JavaScript em um navegador real. Layout, foco visível, letras nas alternativas, labels e navegação HTML foram implementados, mas acessibilidade manual, leitor de tela e funcionamento real do temporizador/polling no Chromebook ainda devem ser conferidos.

1. No notebook, criar professor, carregar quiz demonstrativo, iniciar Rails e descobrir IP local.
2. Conectar dois Chromebooks ao mesmo roteador, testar entrada e projeção; conferir firewall, rede convidada e isolamento dos clientes.
3. Desconectar somente o acesso externo do roteador, mantendo Wi-Fi local. Conferir estilos, scripts e imagem; completar as cinco questões.
4. Atualizar a página de um aluno, interromper e reativar seu Wi-Fi; conferir recuperação pelo cookie e ausência de resposta duplicada.
5. Percorrer formulários e alternativas com Tab/Enter/Espaço; testar zoom de 200%, celular, leitor de tela e contraste no projetor.
6. Repetir a medição com 50 dispositivos/clientes da rede escolar e registrar p95, erros e consistência. Ajustar capacidade apenas a partir dessa medição.
7. Validar operação regular com versões mantidas, HTTPS local, supervisão de processo e rotina de backup. Windows/WSL, firewall escolar e certificados não foram testados aqui.

## Ajuste: encerramento após todas as respostas

A última resposta ativa encerra a rodada na mesma transação, preservando o prazo original para pontuação. O polling também detecta quando a remoção de um participante deixou apenas alunos que já responderam. Salas sem participantes ativos não fecham antecipadamente. Testes confirmam fechamento imediato, sigilo até a revelação e reenvio idempotente.

## Atualização visual responsiva

Aplicado estilo claro inspirado nas referências: menu lateral do professor no desktop (navegação horizontal no celular), painel com atalhos coloridos e métricas reais, entrada com código de seis dígitos, controle com ações ao lado da questão, alternativas com letras, distribuição de respostas, placar e relatório com barras de acerto. Resumo final individual mostra acertos, posição, pontos e ausências por questão, somente após finalizar. Marca vetorial original e ilustração em CSS são locais, sem fontes, imagens ou scripts remotos.

Breakpoints em 1200, 1000, 760 e 480 px reorganizam colunas, controles e navegação. Tabelas mantêm rolagem dentro de seu próprio cartão em telas estreitas. Incluídos link para pular ao conteúdo, foco visível e redução de movimento conforme preferência do dispositivo. Validação de HTML/recursos locais por integração, sintaxe JavaScript, RuboCop e Zeitwerk aprovada. O teste do resumo final confirma resultados individuais diferentes, ausência sem resposta e ausência de resumo antes da finalização. Não foi executado teste visual em navegador nem em dispositivos físicos; conferir nos Chromebooks e celular continua necessário.

## Correção da entrada em outra sala

O cookie anterior só recupera a participação se o código informado corresponde à mesma partida ainda ativa. Outra sala é validada normalmente; códigos encerrados recebem mensagem explícita. Testes cobrem migração de partida finalizada para nova sala, ausência de resumo de conclusão na espera, reconexão sem duplicação e código inválido mesmo com cookie existente.

## Música opcional local

Upload de áudio por quiz (MP3/OGG/WAV/M4A, até 15 MB), snapshot nas novas salas e controles opt-in com volume inicial de 8%, limite visual de 20%, loop e pausa ao fechar a questão ou sair da página. Nenhuma gravação comercial incluída. Integração verifica upload por HTTP, validação de tipo, arquivo local idêntico ao enviado, snapshot preservado após remover o vínculo do quiz e ausência de controles quando não há áudio.

`node test/javascript/music_controller_test.mjs`: aprovado para opt-in, volume inicial, loop, transições entre questões, silenciamento, rejeição de reprodução e limpeza do player. O teste usa um objeto de áudio simulado, não reproduz som real. Teste auditivo em Chrome/Chromebook, formatos/codecs e permissão de reprodução ainda requer navegador físico. API consultada: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play.

## Cadastro de professor pela interface

Nova entrada em `/signup`, acessível pelo login, com nome, e-mail normalizado, senha de no mínimo 12 caracteres e confirmação obrigatória também no servidor. O cadastro autentica a nova conta com sessão renovada. Campos permitidos explícitos; a conta começa sem conteúdo e mantém as restrições de propriedade existentes. E-mail duplicado não altera a conta original. Limite de cinco tentativas por navegador em 15 minutos, sem limitar a turma pelo IP compartilhado. Não há envio de confirmação por e-mail. Testes cobrem cadastro, login subsequente, senha curta, confirmação divergente/ausente, campos de senha vazios no HTML de erro, duplicidade, sessão existente, CSRF e limite por navegador. Alteração local; ainda requer deploy para aparecer em produção.

## Assistente de IA local

Adicionada fila PostgreSQL de pedidos privados com processo `ai:work`, cliente Ollama limitado a loopback, modelo padrão `qwen2.5:1.5b`, opções de memória e descarregamento após geração. Fluxo real: formulário, fila, polling de estado autorizado, revisão editável com confirmação obrigatória e importação transacional/idempotente. Um teste com conexões PostgreSQL independentes confirma que dois processos não geram simultaneamente nem marcam incorretamente o pedido ativo como falha. O teste HTTP usa um servidor TCP local que confere o pedido enviado e devolve respostas controladas; cobre schema, memória/keep_alive, modelo ausente, JSON inválido e limite de tamanho. Os testes de aplicação cobrem rascunho sem quiz salvo, propriedade por professor, validação de parâmetros, espera durante jogo, erro recuperável e edição do gabarito antes de importar.

**Sem medição de inferência real:** Ollama não estava instalado neste ambiente. Instalação e diagnóstico real estão em [IA_LOCAL.md](IA_LOCAL.md); `script/check_ai.rb` mede uma geração no computador de destino sem salvar quizzes. Produção ainda exige migration, deploy, modelo baixado e processo da fila supervisionado. A política inicial do documento de projeto que excluía IA foi ampliada pela solicitação posterior do usuário; os fluxos básicos permanecem independentes da IA.

## Script de instalação da IA no Ubuntu

Adicionado `script/setup_ai.rb`: preflight de aplicação/banco, instalação oficial do Ollama quando ausente, modelo local, configuração sem nuvem, migration/assets, unidade systemd da fila com usuário e Ruby do deploy e diagnóstico real opcional. Opções de arquivo privado de ambiente, reinício explícito do serviço web e simulação sem alterações. Os testes verificam parser sem execução shell, preservação de caracteres em segredos, rejeição de injeção por quebra de linha, unidade com variáveis em arquivo protegido e simulação sem chamadas mutáveis. Sintaxe e `--dry-run` executados; **a instalação efetiva e a geração real ainda devem ser executadas no Ubuntu do usuário**.

## Recuperação automática do ambiente de produção

O instalador agora procura variáveis do ChromeHoot já em produção no diretório exato da aplicação e de arquivos de ambiente locais, com escolha numérica quando há ambiguidade. Apenas variáveis de banco/segredo reconhecidas são copiadas; os valores não aparecem na saída e nenhuma chave nova é criada. Testes com processos simulados verificam a exclusão de outros projetos e de desenvolvimento, leitura sem executar arquivos e preenchimento de variáveis ausentes sem sobrescrever as existentes. Não foi validado contra o servidor remoto do usuário.

## Diagnóstico seguro do instalador

O preflight deixou de rotular qualquer falha como falta de credenciais. Agora identifica chave ausente, chave mestra/credenciais inválidas, autenticação ou conexão PostgreSQL, gems, Ruby e permissões. Exibe apenas códigos, orientações e presença de variáveis/arquivos; não replica a saída bruta do Rails. Testes confirmam classificação e ausência de senhas/URLs no resumo. A descoberta foi ampliada para arquivos de produção em `shared/` e `config/`. O erro específico no servidor remoto ainda requer o novo resumo para identificar a causa.
