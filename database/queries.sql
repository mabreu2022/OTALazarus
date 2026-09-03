/* ============================================================================
   CONSULTAS DE EXEMPLO - CATÁLOGO COMPLETO FPC (Firebird 5.0)
   ============================================================================ */

-- 1. Totalização geral por Severidade
SELECT SEVERITY, COUNT(*) AS TOTAL
FROM FPC_MESSAGES
GROUP BY SEVERITY
ORDER BY TOTAL DESC;

-- 2. Consultar um código FPC específico (ex: 5023, 5024, 10022, 5000)
SELECT 
    CODE, 
    SEVERITY, 
    MESSAGE_PATTERN, 
    DESCRIPTION_PTBR, 
    PROBABLE_CAUSE, 
    MANUAL_SOLUTION, 
    CAN_AUTO_FIX, 
    AUTO_FIX_STRATEGY
FROM FPC_MESSAGES
WHERE CODE = :FPC_CODE;

-- 3. Listar todos os diagnósticos com Correção Rápida (Quick Fix) disponível
SELECT 
    CODE, 
    SEVERITY, 
    MESSAGE_PATTERN, 
    AUTO_FIX_STRATEGY
FROM FPC_MESSAGES
WHERE CAN_AUTO_FIX = 'S'
ORDER BY CODE;

-- 4. Listar todos os Hints e Warnings ordenados por código
SELECT 
    CODE, 
    SEVERITY, 
    MESSAGE_PATTERN
FROM FPC_MESSAGES
WHERE SEVERITY IN ('HINT', 'WARNING')
ORDER BY SEVERITY, CODE;

-- 5. Busca textual por palavra-chave (ex: 'uses', 'variável', 'memória')
SELECT 
    CODE, 
    SEVERITY, 
    MESSAGE_PATTERN
FROM FPC_MESSAGES
WHERE MESSAGE_PATTERN CONTAINING 'não usada'
   OR MESSAGE_PATTERN CONTAINING 'not used'
ORDER BY CODE;
