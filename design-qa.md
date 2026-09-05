# Design QA — painel de voz e usuário

- Source visual truth: `/home/rodrigo/Pictures/Screenshots/Screenshot From 2026-09-04 21-04-18.png`
- Implementation screenshot: `/tmp/user-panel-app-colors.png`
- Combined comparison: `/tmp/user-panel-app-colors-comparison.png`
- Viewport: painel com 270 px de largura; estado conectado, usuário online, câmera e compartilhamento inativos.
- Source pixels: recorte normalizado para 270 × 151 px.
- Implementation pixels: 270 × 144 px, estendido para 270 × 151 px somente para comparação; device scale factor 1.

## Full-view comparison evidence

O painel implementado reproduz a hierarquia da referência: cartão destacado com borda e cantos arredondados, cabeçalho de conexão em duas linhas, ações de mídia em superfície própria, divisor e linha inferior de identidade/controles. A densidade e o ritmo vertical permanecem equivalentes no recorte normalizado. A paleta difere intencionalmente da referência para usar as superfícies neutras do aplicativo.

## Focused region comparison evidence

O componente inteiro já é um recorte focado. Tipografia, ícones, espaçamento, cores, conteúdo e estados foram avaliados na comparação combinada. Não há imagens decorativas ou ativos raster próprios do componente; o avatar real continua vindo do perfil do usuário.

## Findings

- Nenhum P0, P1 ou P2 acionável.
- P3: a referência possui quatro atalhos de sessão, enquanto o app apresenta câmera e compartilhamento. Essa diferença é intencional: atividades e soundboard não existem no produto e não foram simulados com controles sem função.
- P3: a implementação mantém Geist, a fonte do design system do aplicativo, em vez da tipografia proprietária do Discord.

## Required fidelity surfaces

- Fonts and typography: Geist preservada; pesos, tamanhos, truncamento e hierarquia conferidos.
- Spacing and layout rhythm: margens, padding, raios, divisores e alinhamentos conferidos no recorte normalizado.
- Colors and visual tokens: superfícies, bordas, texto e estados usam exclusivamente `AppTokens`; o ping adota a cor semântica da qualidade da conexão.
- Image quality and asset fidelity: sem imagens decorativas; avatar mantém carregamento e recorte circular nativos.
- Copy and content: status, canal, latência, usuário e tooltips preservam o conteúdo real do app.

## Comparison history

- Iteração 1: a estrutura passou, mas ainda usava uma paleta violeta inspirada diretamente na referência.
- Ajuste solicitado: substituir cores locais pelos tokens da aplicação e mover a latência para o hover de um ícone de Wi-Fi.
- Iteração 2: a captura pós-ajuste confirma superfícies neutras, ausência do texto permanente de ms e manutenção da hierarquia; nenhum P0/P1/P2 permanece.

## Implementation checklist

- [x] Agrupar conexão e canal no cabeçalho.
- [x] Mover ações da sessão para uma faixa dedicada.
- [x] Separar controles pessoais na linha inferior.
- [x] Preservar ações, menus de dispositivos e estados existentes.
- [x] Exibir a latência apenas no hover do ícone de Wi-Fi.
- [x] Verificar análise estática e testes do painel.

final result: passed
