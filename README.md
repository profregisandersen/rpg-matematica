# Lendas do Infinito · SESI Gama

(Antes se chamava "Códex do Infinito" e, antes disso, "RPG de Matemática".)

Protótipo de jogo de batalha por turnos para o 6º e o 7º ano: o aluno só age quando acerta uma questão de matemática.

**Versão 2.1 (recompensas)**

- Criaturas novas, as **criaturas geométricas**: cada elemento tem uma forma da matemática (fogo = triângulo, água = círculo, planta = espiral, pedra = hexágono, raio = zigue-zague, infinito = ∞). No estágio 1 a criatura é lisa como o avatar; a cada evolução a forma vira cristal lapidado. Os ovos ganharam a forma do elemento na casca.
- Animações de recompensa: moedas voando até o contador, baú que treme e abre, ovo novo, título novo. Todas duram menos de 3 segundos e pulam com um toque.
- Sons novos: botões, abas, teclado, moedas, compra, baús. Os sons de botões têm uma chave própria nos Ajustes.
- **Baús** comum, raro e épico (moedas, reações, títulos e peças cosplay; item repetido vira moedas). Nunca são vendidos.
- **Passe do Bimestre**, grátis: cada 100 XP no bimestre libera um dos 20 prêmios.
- **Títulos** embaixo do nome (Conta e sala de espera) e **reações** na sala de espera.
- **Coleção cosplay** na loja: ninja, fada, guerreiro, mago, pirata e astronauta (roupa e acessório de cada um).
- Ovos por conquista: nível 10 e 30 do avatar e andar 50 da Torre, além das ilhas com 100% das estrelas.

**Versão 2.0 (celular)**

- Nome novo, **Lendas do Infinito**, com logo e ícone novos e a tela de entrada com o anel das ilhas.
- Visual novo em todas as seções: azul-noite, molduras douradas com cantos cortados e as fontes Cinzel e Sora.
- Toda a arte refeita em pixel art: avatar Chibi (frente e costas, com todas as opções de antes), 24 criaturas, 10 monstros, 5 chefões de ilha, o Chefão da Sala, as ilhas do mapa e 8 cenários de batalha.
- O save não mudou: contas, progresso, moedas, itens e turmas continuam iguais.
- A versão 1.0 continua em `v1/` por algumas semanas, como plano de volta.
- O formato de computador ainda usa o arranjo da 1.0 com o visual novo; ele será refeito depois.

**Versão 1.0 (com servidor)**

- Contas com usuário e senha criados pelo próprio aluno. O progresso fica salvo na nuvem (Supabase), e o aluno continua em qualquer aparelho.
- O aluno entra na turma com o código de 5 letras. O professor vê presença, mapa de calor, ranking e pedidos de nick, e pode criar senha nova para o aluno.
- Professor cria a conta com o código de professor e entra rápido com um PIN pessoal.
- Salas e Chefão da Sala pelo Supabase Realtime.
- Quem jogou o teste pode trazer o progresso do aparelho para a conta.
- O banco está em `servidor/schema.sql`. Enquanto o endereço do Supabase não estiver configurado, o jogo funciona como protótipo, com tudo salvo no aparelho.

**Versão 0.05**

- Entrada com dois cartões: **Sou aluno** (e-mail institucional ou usuário e senha) e **Sou professor** (PIN de 4 dígitos; no protótipo o PIN de teste é 2027, e ele trava por 5 minutos depois de 5 erros).
- As 24 criaturas redesenhadas: o ovo choca no nível 1 e evolui nos níveis 11 e 37, com animação de eclosão e de evolução. A roleta tem o raro Ovo do Infinito (2%).
- Aba **Criaturas** com o ninho e o botão **Minha coleção**, onde o aluno escolhe a criatura que vai batalhar.
- Treino Solo com monstros selvagens sorteados em cada ilha e um chefão por ilha. Fazer 3 estrelas em todas as etapas de uma ilha dá o ovo daquele elemento (ou +150 XP e +80 moedas, se o aluno já tiver).
- Batalha na Arena no estilo "treinador atrás": a criatura luta na frente do avatar, com o escudo da liga ao lado do nick.
- Fraquezas de elemento: Água → Fogo → Planta → Pedra → Raio → Água. Quem ataca com vantagem dá +5 ("É super efetivo!"), e quem ataca em desvantagem dá −5. O Infinito dá +5 contra todos, e ninguém tem vantagem contra ele.
- Curar recupera 30 de vida na Arena (15 no Chefão da Sala), e o Escudo bloqueia só o primeiro golpe da rodada e depois quebra.
- Escudo da liga ao lado do nick na sala de espera, no resultado e no topo do Início; o resultado mostra os pontos de liga ganhos.
- Filtro de palavrões nos nicks (no cadastro, na troca de nick e quando alguém entra numa sala).
- O professor aparece como **[GM]** antes do nick para todos.
- **Ligas do semestre** dentro da aba Conta: 1º lugar +25, 2º +15, 3º +5; 100 pontos sobem uma divisão.
- Para o professor: aba **Turma** (turmas com código, ficha do aluno com presença e mapa de calor, ranking só para professores) e o evento **Chefão da Sala** no JOGAR, com placar de dano ao vivo.

## Como jogar

1. Abra o link do jogo no celular, no tablet ou no computador.
2. Entre, monte o avatar e gire a roleta do ovo.
3. Toque em **JOGAR**: um cria a sala, e os outros escolhem **Entrar com código**.
4. Depois da primeira partida, o mapa de treino aparece na aba Início.
5. Professor: entre com o PIN e use **JOGAR › Chefão da Sala** para abrir o evento. Os alunos entram com o código pelo **Entrar com código**. Os alunos que entram nas salas do professor aparecem na aba **Turma** do aparelho dele.

## Como funciona a conexão

O aparelho de quem cria a sala controla a partida: sorteia as perguntas, confere as respostas e calcula os golpes. Os outros aparelhos se ligam a ele pela biblioteca [PeerJS](https://peerjs.com), que só apresenta os aparelhos uns aos outros. O jogo não guarda nome, e-mail nem notas em servidor: o perfil fica salvo só no aparelho de cada aluno.

Para testar sem internet entre abas do mesmo navegador, abra o jogo com `?local=1` no fim do endereço.

## Arquivos

- `index.html`: o jogo inteiro num arquivo só.

Projeto de Régis Andersen e Nathan, área de Matemática do SESI Gama.
