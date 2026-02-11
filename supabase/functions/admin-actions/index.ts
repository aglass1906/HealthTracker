
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const authHeader = req.headers.get('Authorization')
        console.log("Received Auth Header:", authHeader ? "Present" : "Missing")

        if (!authHeader) {
            console.log("Error: Missing Authorization header")
            return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
                status: 401,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        const supabaseClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: authHeader } } }
        )

        const { data: { user }, error: userError } = await supabaseClient.auth.getUser()

        if (userError) {
            console.log("Error fetching user:", userError)
        }
        if (!user) {
            console.log("Error: No user found for token")
        }

        if (userError || !user) {
            return new Response(JSON.stringify({ error: 'Unauthorized', details: userError }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 401,
            })
        }

        const serviceRoleClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const { data: profile, error: profileError } = await serviceRoleClient
            .from('profiles')
            .select('is_admin')
            .eq('id', user.id)
            .single()

        if (profileError || !profile?.is_admin) {
            return new Response(JSON.stringify({ error: 'Forbidden: Admin access required' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 403,
            })
        }

        const { action, ...payload } = await req.json()

        if (action === 'get_users') {
            const { data: { users }, error: listError } = await serviceRoleClient.auth.admin.listUsers()

            if (listError) throw listError

            const { data: profiles, error: profilesError } = await serviceRoleClient
                .from('profiles')
                .select('id, display_name, email')

            if (profilesError) throw profilesError

            const mergedUsers = users.map((u: any) => {
                const profile = profiles.find((p: any) => p.id === u.id)
                return {
                    id: u.id,
                    email: u.email,
                    display_name: profile?.display_name || u.user_metadata?.display_name || 'N/A',
                    created_at: u.created_at
                }
            })

            return new Response(JSON.stringify({ users: mergedUsers }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            })
        }

        if (action === 'update_password') {
            console.log("Processing update_password for user:", payload.userId)
            const { userId, newPassword } = payload
            if (!userId || !newPassword) {
                console.log("Error: Missing userId or newPassword")
                return new Response(JSON.stringify({ error: 'Missing userId or newPassword' }), {
                    status: 400,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                })
            }

            const { data, error: updateError } = await serviceRoleClient.auth.admin.updateUserById(
                userId,
                { password: newPassword }
            )

            if (updateError) {
                console.log("Error updating password:", JSON.stringify(updateError))
                throw updateError
            }

            return new Response(JSON.stringify({ success: true, message: 'Password updated successfully' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            })
        }

        return new Response(JSON.stringify({ error: 'Invalid action' }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
        })

    } catch (error) {
        return new Response(JSON.stringify({
            error: error.message || 'Unknown error',
            details: error
        }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        })
    }
})
