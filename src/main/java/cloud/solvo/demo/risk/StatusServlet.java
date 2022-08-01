package cloud.solvo.demo.risk;

import javax.servlet.*;
import javax.servlet.http.*;
import javax.servlet.annotation.*;

import java.io.IOException;

@WebServlet(name = "StatusServlet", value = "/status")
public class StatusServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setStatus(200);
        response.getWriter().write("OK");
    }
}
