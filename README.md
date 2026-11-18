# RPG de Matemática · SESI Gama

Protótipo de jogo de batalha por turnos para o 6º e o 7º ano: o aluno só age quando acerta uma questão de matemática.

**Versão 0.03 (multijogador)**

- Qualquer pessoa cria uma sala e recebe um código de 5 letras.
- Os colegas entram com o código, cada um no próprio aparelho (de 2 a 4 jogadores).
- O anfitrião pode completar a sala com robôs.

## Como jogar

1. Abra o link do jogo no celular, no tablet ou no computador.
2. Entre, monte o avatar e gire a roleta do ovo.
3. Toque em **JOGAR**: um cria a sala, e os outros escolhem **Entrar com código**.

## Como funciona a conexão

O aparelho de quem cria a sala controla a partida: sorteia as perguntas, confere as respostas e calcula os golpes. Os outros aparelhos se ligam a ele pela biblioteca [PeerJS](https://peerjs.com), que só apresenta os aparelhos uns aos outros. O jogo não guarda nome, e-mail nem notas em servidor: o perfil fica salvo só no aparelho de cada aluno.

Para testar sem internet entre abas do mesmo navegador, abra o jogo com `?local=1` no fim do endereço.

## Arquivos

- `index.html`: o jogo inteiro num arquivo só.

Projeto de Régis Andersen e Nathan, área de Matemática do SESI Gama.
