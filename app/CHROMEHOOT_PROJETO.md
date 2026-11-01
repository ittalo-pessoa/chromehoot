# ChromeHoot — projeto para implementação com Codex no VS Code

## 1. Proposta

Plataforma de quizzes educacionais gamificados para qualquer disciplina, desenvolvida em Ruby on Rails com PostgreSQL. O professor cria perguntas, abre uma partida e acompanha respostas e ranking. Alunos participam pelos navegadores dos Chromebooks, conectados à mesma rede Wi-Fi do servidor.

O uso em sala deve funcionar sem internet após a instalação. O notebook do professor hospeda Rails e PostgreSQL; um roteador fornece a rede local. Instalação de dependências e atualizações podem exigir internet previamente. Não depender de serviços externos, fontes remotas, CDN, autenticação social ou APIs pagas durante as partidas.

Público inicial: turmas de aproximadamente 40–45 estudantes da ECIT Guarabira Dom Marcelo Pinto Carvalheira. Planejar validação com pelo menos 50 participantes simulados. Isso é uma meta de teste, não garantia antecipada de desempenho.

## 2. Escopo da primeira versão

- Login e logout de professores; sem cadastro público de professor.
- Painel com quizzes, partidas recentes e resumo de desempenho.
- Cadastro de quiz: título, descrição e disciplina.
- Questões de múltipla escolha, de duas a cinco alternativas, exatamente uma correta.
- Tempo por questão entre 10 e 180 segundos; padrão de 30 segundos.
- Imagem opcional na questão, armazenada no servidor local.
- Duplicação de quiz e ordenação de questões.
- Sala com código numérico de seis dígitos, preservando zeros à esquerda.
- Entrada de alunos por código e apelido, sem conta ou e-mail.
- Sala de espera com lista de participantes.
- Controle do professor para abrir questão, fechar respostas, revelar resultado, avançar e finalizar.
- Placar parcial, pódio final e histórico.
- Relatório por partida e exportação CSV.
- Recuperação de sessão do aluno após atualização da página ou queda momentânea da rede.

Fora da primeira versão: IA, aplicativo móvel, integração com SIAGE, cadastro nominal permanente de alunos, vídeos externos e torneios entre escolas. Não implementar esses recursos antes do fluxo básico estar validado.

## 3. Arquitetura proposta

Aplicação Rails monolítica, com HTML/ERB, Hotwire (Turbo e Stimulus), PostgreSQL e Active Storage local. CSS e JavaScript servidos localmente. Interface responsiva em português do Brasil.

Para a primeira versão, usar consultas HTTP periódicas para sincronização, evitando infraestrutura adicional de WebSocket. Alunos consultam o estado a cada dois segundos durante a questão e a cada quatro segundos na espera. Suspender consultas em páginas encerradas e evitar requisições simultâneas sobrepostas. A tela de controle pode atualizar contadores a cada dois segundos. Cada resposta de estado precisa ser pequena e ter autorização própria.

O servidor é a autoridade sobre estado, prazo, acerto e pontuação. O relógio do navegador serve apenas para exibição. O estado devolve o horário atual do servidor e o prazo de fechamento para compensar diferenças de relógio. A experiência de tempo real é por atualização periódica, com pequeno atraso esperado.

Usar uma versão estável de Rails compatível com o Ruby instalado. Antes de gerar código, o Codex deve consultar a documentação oficial da versão escolhida, verificar o ambiente e registrar as versões no README e nos arquivos de dependências. Não misturar exemplos de versões diferentes. Não fixar números de versão por suposição.

## 4. Perfis e permissões

Professor: acessa somente seus quizzes, partidas e relatórios. Gerencia questões e participantes, conduz partidas e exporta resultados. Toda consulta deve ser restrita ao professor autenticado; conhecer um ID não concede acesso.

Aluno: entra apenas em sala aguardando início, responde à questão atual e visualiza resultados liberados. Sua identidade é uma credencial aleatória emitida pelo servidor e guardada em cookie assinado, HttpOnly e SameSite adequado. Não aceitar participant_id enviado pelo cliente como prova de identidade. Não usar apelido ou código da sala como credencial individual.

Tela de projeção: aberta a partir da sessão autenticada do professor; mostra código, questão e placar. A tela de controle mantém botões e informações administrativas. Alunos nunca recebem os dados privados do professor.

## 5. Modelo de dados

Usar classes e tabelas em inglês para manter as convenções Rails; textos da interface em português.

| Modelo | Campos principais | Relações e regras |
|---|---|---|
| User | name, email, password_digest | Professor; e-mail único normalizado; senha com has_secure_password |
| Quiz | user_id, title, description, subject, archived_at | Pertence ao professor; possui questões |
| Question | quiz_id, statement, position, time_limit_seconds | Possui alternativas; imagem opcional via Active Storage |
| Choice | question_id, text, correct, position | De duas a cinco por questão; exatamente uma correta no quiz publicável |
| GameSession | user_id, quiz_id, join_code, status, started_at, finished_at | Partida; usa cópia imutável das questões |
| SessionQuestion | game_session_id, statement, position, time_limit_seconds | Snapshot da questão e imagem quando a partida é criada |
| SessionChoice | session_question_id, text, correct, position | Snapshot das alternativas; imutável |
| Participant | game_session_id, nickname, normalized_nickname, credential_digest, removed_at | Apelido único por partida; credencial aleatória armazenada como digest |
| Round | game_session_id, session_question_id, status, opened_at, closes_at, closed_at | Uma rodada por questão da partida; ordem controlada pelo servidor |
| Answer | round_id, participant_id, session_choice_id, received_at, correct, points | Uma resposta por participante e rodada |

Criar chaves estrangeiras, índices e restrições no PostgreSQL. Índices únicos: e-mail normalizado; código da sala; apelido normalizado por partida; resposta por participante/rodada; rodada por questão da partida; posições dentro do respectivo pai. Garantir no serviço que participante, alternativa, questão e rodada pertencem à mesma partida. Validações de aplicação e testes devem cobrir essas associações.

As alternativas corretas exigem validação transacional ao salvar a questão completa, sem impedir estados intermediários do formulário. Impedir abrir uma partida com quiz vazio ou questões inválidas. Partidas guardam snapshots para alterações posteriores no quiz não mudarem histórico, gabarito ou pontuação. Não apagar partidas históricas por exclusão em cascata do quiz: preferir arquivamento.

## 6. Estados e fluxo

Partida: waiting → running → finished. Também pode passar de waiting ou running para cancelled. Estados terminais não aceitam novas respostas ou participantes.

Rodada: pending → open → closed → revealed. Só uma rodada pode estar aberta na partida. O professor abre a primeira questão após iniciar. Ao expirar o prazo, ela é considerada fechada mesmo se nenhum job estiver executando. O próximo acesso fecha a rodada de forma idempotente; o endpoint de resposta sempre verifica closes_at. O professor também pode fechar antes do prazo.

Somente depois de fechar é permitido revelar o resultado. Avançar exige rodada anterior revelada; a próxima questão fica aguardando o professor abri-la. Finalizar exige confirmar que não há rodada aberta ou fechá-la na mesma transação. Requisições repetidas não podem criar rodadas duplicadas, reabrir rodadas ou somar pontos novamente.

Usar transações e bloqueio da partida/rodada nos serviços de transição e resposta, com ordem de bloqueio consistente. O limite de aceitação é o instante em que o servidor valida a resposta dentro da transação; não o instante em que o aluno clicou.

Na reconexão, o cookie recupera o participante, o servidor informa o estado atual e se ele já respondeu. Sem a credencial, não recuperar automaticamente alguém apenas pelo apelido. Participantes removidos não voltam a responder, mas seu histórico permanece.

## 7. Pontuação

Resposta errada ou ausência: zero ponto. Resposta correta: 500 pontos de base e até 500 de bônus por velocidade.

    duration_ms = closes_at - opened_at, convertido para milissegundos
    elapsed_ms = received_at - opened_at, limitado a 0..duration_ms
    bonus = floor(500 × (duration_ms - elapsed_ms) / duration_ms)
    points = 500 + bonus

Usar o prazo original da rodada no cálculo mesmo se o professor fechar antecipadamente. Registrar received_at pelo relógio do servidor. Aceitar somente enquanto a rodada estiver aberta e received_at < closes_at. Salvar acerto e pontos uma única vez, na mesma transação da resposta. Reenvio da mesma resposta devolve o resultado persistido; tentativa de trocar alternativa após responder é recusada.

Ranking por soma de pontos, depois quantidade de acertos e depois menor soma de tempo das respostas corretas. Persistindo empate, compartilhar a colocação; ordenar nomes apenas para apresentação. Calcular o total a partir das respostas persistidas para evitar contadores inconsistentes.

## 8. Telas

1. Página inicial: identidade ChromeHoot, entrada por código e acesso do professor.
2. Login do professor.
3. Painel do professor: quizzes e partidas recentes.
4. Editor de quiz e formulário de questões com alternativas.
5. Sala de espera do professor: código grande, participantes e iniciar.
6. Controle da partida: estado, temporizador, contagem de respostas e ações.
7. Projeção: enunciado, alternativas, resultado agregado e ranking.
8. Entrada do aluno: código e apelido.
9. Espera do aluno: confirmação de entrada e aviso de início.
10. Questão do aluno: botões grandes e confirmação de envio.
11. Resultado do aluno após revelação, placar e pódio final.
12. Histórico e relatório: participantes, acertos, erros, ausências, pontos e desempenho por questão.

Identidade visual: fundo roxo ou azul escuro, cartões claros, destaque amarelo e alternativas coloridas com letras e símbolos. Não usar apenas cores para distinguir opções. Tipografia local, contraste adequado, foco visível e navegação por teclado. Evitar imagens ou sons obrigatórios. Não copiar marcas ou elementos proprietários de outras plataformas.

## 9. Contratos HTTP e segurança

Rotas sugeridas, a ajustar às convenções Rails:

- /login e /logout: autenticação de professor.
- /teacher/quizzes e /teacher/quizzes/:id/questions: gestão restrita ao proprietário.
- /teacher/game_sessions: criação, histórico e relatórios.
- /teacher/game_sessions/:id/start, /open_question, /close_question, /reveal, /advance, /finish: comandos autenticados por POST/PATCH.
- /teacher/game_sessions/:id/projector: projeção autenticada.
- /join: entrada em sala.
- /play: tela do participante autenticado pelo cookie.
- /play/state: estado sanitizado para o participante.
- /play/answer: resposta por POST.

Proteger mutações com CSRF. Nunca enviar correct, gabarito ou respostas de colegas no HTML, JSON, atributos data ou JavaScript enquanto a questão estiver aberta. Na primeira versão, gabarito e acerto individual só ficam visíveis após revealed. Ao receber a resposta, retornar apenas confirmação, sem revelar acerto ou pontos antecipadamente. O ranking só atualiza publicamente após a revelação.

Limitar comprimento de apelidos e textos; escapar saída; validar imagens por tipo e tamanho. Gerar códigos com aleatoriedade segura e tratar colisões no banco. Limitar tentativas de entrada e login, sem bloquear uma turma inteira por compartilhar o mesmo IP. Não usar GET para comandos que alteram o jogo. Exportação CSV deve neutralizar campos iniciados por caracteres de fórmula, como =, +, - e @.

## 10. Organização do código

Controllers pequenos; regras de jogo em serviços:

- GameSessions::Create: valida quiz e cria snapshots.
- GameSessions::Start, Finish e Cancel.
- Rounds::Open, Close, Reveal e Advance.
- Answers::Submit: valida identidade, vínculo, prazo, unicidade e calcula pontos.
- Rankings::Build: ranking e desempates.
- Reports::ExportCsv: relatório autorizado e CSV seguro.

Usar presenters ou serializers explícitos para estado público e privado. Evitar serializar objetos completos com as_json. Criar componentes parciais para alternativas, temporizador, placar e notificações.

## 11. Desenvolvimento por etapas

Etapa 1 — Base: ambiente, Rails/PostgreSQL, autenticação, layout local e README. Entrega: professor entra e sai com sessão protegida.

Etapa 2 — Conteúdo: CRUD de quizzes e questões, validações, ordenação e imagem. Entrega: quiz publicável com alternativas válidas.

Etapa 3 — Partida: snapshots, códigos, espera, entrada e identidade do participante. Entrega: dois navegadores acessam a mesma sala.

Etapa 4 — Jogo: máquina de estados, prazo, resposta, pontuação, polling e reconexão. Entrega: partida completa sem internet externa.

Etapa 5 — Resultados: ranking, pódio, histórico e CSV. Entrega: relatório corresponde às respostas salvas.

Etapa 6 — Validação: testes críticos, acessibilidade, teste com participantes simulados e roteiro de uso na rede local. Registrar resultados e limitações observadas.

Não substituir funcionalidades por telas demonstrativas. Em cada etapa, implementar, executar os testes aplicáveis e registrar o que funciona antes de avançar.

## 12. Testes de aceitação obrigatórios

- Professor A não lê nem modifica quiz, partida ou relatório do professor B.
- Código inválido, apelido repetido e sala encerrada são tratados com mensagens claras.
- Questões sem resposta correta ou com várias corretas não iniciam partida.
- Editar quiz não altera uma partida já criada.
- Duas respostas concorrentes do mesmo participante geram um único registro.
- Respostas fora do prazo, de outra rodada ou com alternativa de outra questão são recusadas.
- Corrida entre fechar rodada e responder tem resultado consistente.
- Atualizar página e reconectar recupera o participante sem duplicação.
- Gabarito e pontuação permanecem ocultos antes da revelação, inclusive nas respostas de rede.
- Cliques repetidos em iniciar, avançar e finalizar são idempotentes.
- Ranking e CSV conferem com os registros persistidos, inclusive empates e ausências.
- Imagens, estilos e scripts carregam com internet externa desconectada e rede local ativa.
- Teste de carga registra latência, erros e consistência com 50 participantes; não afirmar suporte sem medir.

## 13. Dados de demonstração

Criar seeds idempotentes com um quiz de Introdução à Informática e cinco questões originais: hardware, software, memória RAM, sistema operacional e rede local. Conta inicial recebe senha por variável de ambiente ou procedimento local documentado; não gravar senha pública fixa no repositório. Seeds de demonstração devem ser separados de dados de produção.

## 14. Execução no VS Code e rede da escola

Pré-requisitos: Git, VS Code com Codex, Ruby e Rails compatíveis, PostgreSQL e ferramenta de instalação de dependências exigida pela configuração escolhida. No Windows, usar preferencialmente ambiente Linux pelo WSL2; documentar acesso à rede local considerando firewall e encaminhamento do WSL. Não assumir que liberar apenas o Rails é suficiente nesse ambiente.

Após o Codex verificar as versões e instalar o Rails escolhido, o comando base é:

    rails new chromehoot --database=postgresql
    cd chromehoot
    code .

Se a pasta já contém uma aplicação Rails, inspecionar antes e não gerar outra por cima. Dentro do projeto, colocar este documento como CHROMEHOOT_PROJETO.md e enviar ao Codex o comando da seção seguinte.

Ao concluir a implementação, o README precisa orientar configuração de DATABASE_URL ou database.yml sem segredos versionados, criação/migração do banco, usuário inicial, execução de testes e inicialização. Para acesso pela rede, o servidor Rails pode ser iniciado com:

    bin/rails server -b 0.0.0.0 -p 3000

Alunos usam http://IP_LOCAL_DO_SERVIDOR:3000 na mesma rede. O IP é descoberto no notebook; não usar localhost nos Chromebooks. Conferir isolamento entre clientes no roteador, firewall e rede convidada. Não expor a porta do PostgreSQL aos alunos. Documentar que execução em modo de desenvolvimento serve para validação local; operação regular exige configuração de execução apropriada, processo supervisionado e rotina de backup.

O backup deve incluir PostgreSQL e arquivos locais do Active Storage. Documentar restauração e testar ao menos uma recuperação em ambiente separado. A escola precisa manter o servidor ligado e a rede local ativa durante a partida.

## 15. Prompt inicial para colar no Codex

Leia integralmente CHROMEHOOT_PROJETO.md e implemente o ChromeHoot nesta pasta, em Ruby on Rails com PostgreSQL. Primeiro inspecione arquivos existentes, instruções AGENTS.md e versões instaladas. Não sobrescreva trabalho existente. Consulte documentação oficial ao escolher a versão e APIs do Rails. Apresente um plano curto e comece a execução pela etapa 1, avançando pelas etapas com validação incremental.

Priorize o fluxo real completo: login do professor, criação de quiz válido, sala com código, entrada de alunos, rodadas sincronizadas pelo servidor, resposta única dentro do prazo, revelação, ranking e histórico. Siga os modelos, snapshots, permissões e regras de concorrência deste documento. Interface em português, recursos locais, PostgreSQL real e nenhuma dependência de internet durante as partidas.

Crie migrations, modelos, controllers, serviços, views, estilos, seeds e testes necessários. Não entregue apenas um plano, protótipo visual ou dados simulados. Não use SQLite como substituto. Não publique nem configure hospedagem externa. Execute os testes disponíveis; se algo não puder ser executado, registre o motivo e o comando pendente sem afirmar que passou. Mantenha o README atualizado com versões, preparação do ambiente, comandos de execução, acesso pela rede local e limitações verificadas. Ao final, informe o que foi implementado, os testes executados e como abrir o ChromeHoot.
