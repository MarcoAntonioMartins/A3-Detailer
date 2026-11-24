# Histórico de versões

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e as versões seguem o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [0.3.4] - 2026-11-24
### Corrigido
- Pilares com mais de um console: cada console ou saliência ganha o seu corte,
  mesmo que seja curto. Antes, com o limite de 4 cortes, o console de cima do
  PPF04 ficava sem corte e o D-D mostrava só o console lateral.
### Alterado
- Até 6 cortes por prancha (eram 4). Na escolha, a seção principal e um corte
  por tipo de saliência entram primeiro; as vagas que sobram vão para as seções
  mais compridas.

## [0.3.3] - 2026-11-24
### Alterado
- Layout ajustado pela prancha real do PPF04 e pela referência PPF1:
  - a coluna do modelo 3D fica só da largura do desenho, e o espaço que sobra
    vai para as vistas (PPF04 passou de 1:40 para 1:30, como na referência);
  - os cortes vão para a faixa livre entre as vistas e o carimbo quando cabem
    ali em escala maior; a escala dos cortes nunca passa de 1:10;
  - rótulos de insertos ficam acima da peça, com linha de chamada até o
    inserto, sem escrever sobre as arestas nem sobre marcas de corte e cotas.
### Corrigido
- Cotas locais de recorte: a referência é o topo que ocupa a maior parte do
  comprimento. Um console saliente não transforma mais o resto da peça em
  "rebaixo" (apareciam cotas de 25 e 30 com linhas de chamada soltas).

## [0.3.2] - 2026-11-24
### Corrigido
- Cadeias de cotas não somem mais quando algum trecho é pequeno: todos os trechos
  são cotados e o texto dos trechos pequenos muda de lado ou sai para fora das
  linhas de chamada, sem encavalar com os vizinhos nem com as marcas de corte.
### Adicionado
- Cota local da profundidade de cada recorte ou rebaixo na borda superior das
  vistas (ex.: dente na ponta e recorte de borda das lajes).
### Alterado
- Em lajes e placas, a face grande (comprimento × largura) passa a se chamar
  "VISTA SUPERIOR" e a espessura "VISTA LATERAL". Pilares e vigas não mudam.

## [0.3.1] - 2026-11-02
### Alterado
- Projeto renomeado para **A3-Detailer**: nome no Gerenciador de extensões,
  menu do SketchUp, README e arquivo `.rbz` (`A3-Detailer-<versão>.rbz`).
- O nome interno (pasta `detalhamento_pm` e módulo `DetalhamentoPM`) foi mantido,
  para que quem já instalou a versão anterior atualize sem duplicar a extensão.

## [0.3.0] - 2026-11-02
### Adicionado
- Saída em **PDF vetorial A3** gerada pelo próprio plugin (sem AutoCAD).
- Opção de formato: PDF por peça, PDF único (uma prancha por página), PDF e DXF, ou só DXF.
- Estilos de impressão por camada (espessura, cor e tracejado).
- Testes automatizados e simulação da API do SketchUp para rodar fora do programa.

## [0.2.0] - 2026-11-02
### Adicionado
- Prancha **A3 de formas** por tipo de peça, em DXF (NBR 16752).
- Vista superior e vista lateral com **linhas ocultas** tracejadas e escala automática.
- **Cortes automáticos** nos trechos onde a seção muda, com hachura e cotas.
- Cotas em cadeia e totais, posição de insertos (alças, chapas) e marcas de corte.
- Modelo 3D isométrico, quadro resumo (dimensões, volume, peso, fck), revisões e carimbo.
- Nome de arquivo no padrão `PREFIXO-OBRA-DET-PEÇA-Rxx`.
### Removido
- Detalhamento desenhado dentro do modelo do SketchUp (substituído pelas pranchas).

## [0.1.0] - 2026-11-02
### Adicionado
- Primeira versão: vistas 2D cotadas (superior, frontal e lateral) desenhadas
  ao lado do modelo, agrupando peças iguais.
- Filtro por tags e exportação da lista de peças em CSV.
