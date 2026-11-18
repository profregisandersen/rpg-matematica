# RPG de Matemática · SESI Gama

Protótipo de jogo de batalha por turnos para o 6º e o 7º ano: o aluno só age quando acerta uma questão de matemática.

**Versão 0.04**

- Salas multijogador com código de 5 letras (de 2 a 4 jogadores, com robôs opcionais).
- Início com missões do dia, baú e o mapa de treino: todos começam na Adição e liberam as etapas em sequência.
- Treino Solo na arena: cada acerto faz o ovo atacar o boneco de treino com o golpe do seu elemento.
- Abas Conta, Minha Criatura (cuidados com o ovo) e Estatísticas (acertos por conteúdo, rivais e botão Treinar).

## Como jogar

1. Abra o link do jogo no celular, no tablet ou no computador.
2. Entre, monte o avatar e gire a roleta do ovo.
3. Toque em **JOGAR**: um cria a sala, e os outros escolhem **Entrar com código**.
4. Depois da primeira partida, o mapa de treino aparece na aba Início.

## Como funciona a conexão

O aparelho de quem cria a sala controla a partida: sorteia as perguntas, confere as respostas e calcula os golpes. Os outros aparelhos se ligam a ele pela biblioteca [PeerJS](https://peerjs.com), que só apresenta os aparelhos uns aos outros. O jogo não guarda nome, e-mail nem notas em servidor: o perfil fica salvo só no aparelho de cada aluno.

Para testar sem internet entre abas do mesmo navegador, abra o jogo com `?local=1` no fim do endereço.

## Arquivos

- `index.html`: o jogo inteiro num arquivo só.

Projeto de Régis Andersen e Nathan, área de Matemática do SESI Gama.
