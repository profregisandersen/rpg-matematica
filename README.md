# RPG de Matemática · SESI Gama

Protótipo de jogo de batalha por turnos para o 6º e o 7º ano: o aluno só age quando acerta uma questão de matemática.

**Versão 0.05**

- Entrada com dois cartões: **Sou aluno** (e-mail institucional ou usuário e senha) e **Sou professor** (PIN de 4 dígitos; no protótipo o PIN de teste é 2027, e ele trava por 5 minutos depois de 5 erros).
- As 24 criaturas redesenhadas: o ovo choca no nível 1 e evolui nos níveis 11 e 37, com animação de eclosão e de evolução. A roleta tem o raro Ovo do Infinito (2%).
- Aba **Criaturas** com o ninho e o botão **Minha coleção**, onde o aluno escolhe a criatura que vai batalhar.
- Treino Solo com monstros selvagens sorteados em cada ilha e um chefão por ilha. Fazer 3 estrelas em todas as etapas de uma ilha dá o ovo daquele elemento (ou +150 XP e +80 moedas, se o aluno já tiver).
- Batalha na Arena no estilo "treinador atrás": a criatura luta na frente do avatar, com o escudo da liga ao lado do nick.
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
