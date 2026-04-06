-- ==========================================
-- SCRIPT DE INICIALIZACIÓN: DON TOLTO
-- Descripción: Creación de Tablas, Índices y RLS
-- Fecha: 2026-04-05
-- ==========================================

-- 1. LIMPIEZA (Opcional - Usar con precaución)
-- DROP TABLE IF EXISTS performance;
-- DROP TABLE IF EXISTS projections;
-- DROP TABLE IF EXISTS draws;

-- 2. TABLAS PRINCIPALES

-- Sorteos Reales (Histórico)
CREATE TABLE IF NOT EXISTS draws (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draw_date DATE NOT NULL,
    numbers INTEGER[] NOT NULL, -- Array 5 números
    superbalota INTEGER NOT NULL, -- 1-16
    type VARCHAR(20) NOT NULL CHECK (type IN ('baloto', 'revancha')),
    is_manual BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(draw_date, type)
);

-- Proyecciones (Estrategias Generadas)
CREATE TABLE IF NOT EXISTS projections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_draw_date DATE NOT NULL,
    strategy_name VARCHAR(50) NOT NULL,
    numbers INTEGER[] NOT NULL,
    superbalota INTEGER NOT NULL,
    type VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Rendimiento (Evaluación de Estrategias)
CREATE TABLE IF NOT EXISTS performance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draw_id UUID REFERENCES draws(id) ON DELETE CASCADE,
    strategy_name VARCHAR(50) NOT NULL,
    hits_count INTEGER NOT NULL, -- Cantidad números acertados (0-5)
    has_superbalota BOOLEAN NOT NULL,
    score DECIMAL(5,2) NOT NULL, -- Puntuación ponderada
    category VARCHAR(20) NOT NULL, -- e.g., '1+SB', '3+0', etc.
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. OPTIMIZACIÓN (ÍNDICES GIN PARA ARRAYS)
CREATE INDEX IF NOT EXISTS idx_draws_numbers ON draws USING GIN (numbers);
CREATE INDEX IF NOT EXISTS idx_projections_numbers ON projections USING GIN (numbers);
CREATE INDEX IF NOT EXISTS idx_performance_strategy ON performance (strategy_name);

-- 4. SEGURIDAD (RLS - ROW LEVEL SECURITY)

-- Habilitar RLS
ALTER TABLE draws ENABLE ROW LEVEL SECURITY;
ALTER TABLE projections ENABLE ROW LEVEL SECURITY;
ALTER TABLE performance ENABLE ROW LEVEL SECURITY;

-- Políticas para draws (Lectura pública para autenticados)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public Read for Auth users') THEN
        CREATE POLICY "Public Read for Auth users" ON draws FOR SELECT USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- Políticas para projections (Solo Admin/Auth puede operar)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admin CRUD on projections') THEN
        CREATE POLICY "Admin CRUD on projections" ON projections ALL USING (auth.role() = 'authenticated');
    END IF;
END $$;

-- Políticas para performance (Solo Admin/Auth puede operar)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Admin CRUD on performance') THEN
        CREATE POLICY "Admin CRUD on performance" ON performance ALL USING (auth.role() = 'authenticated');
    END IF;
END $$;
